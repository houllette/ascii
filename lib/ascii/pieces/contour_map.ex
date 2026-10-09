defmodule Ascii.Pieces.ContourMap do
  @moduledoc """
  An island in contour lines, its hills slowly reshaping.

  An island drawn as survey lines, with a dotted line offshore, its hills
  slowly reshaping. Each line keeps to the one cell nearest it, so it stays
  one stroke thick at any angle.

  Ported from `src/pieces/contour-map.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "contour map",
    category: :nature,
    note: "an island in contour lines, its hills slowly reshaping",
    cols: 72,
    rows: 20,
    fps: 8,
    loop: 60
  }

  @cols 72
  @rows 20
  @n 72 * 20
  # Cell width and height, in ems.
  @cw 0.6
  @rh 1.2
  # Height between neighbouring contour lines.
  @level 0.26
  # Where in the drift the loop is centred, in seconds.
  @start 280
  # Seconds for the hills to come back round.
  @period 60
  # How far each swell's phase wanders, in radians.
  @swing 1.15
  # Lines closer than this, in ems, keep only every other one.
  @crowd 1
  # Pieces of line shorter than this are dropped.
  @speck 4
  # The least the swells leave of the hill.
  @floor 0.55

  # Swells laid over one long hill: wavenumbers per em, phase, drift, height,
  # and where in the loop each one wanders, so the shape never just plays
  # backwards.
  @waves [
    {0.21, 0.08, 0.0, 0.055, 0.51, 0},
    {-0.13, 0.27, 1.7, -0.035, 0.42, 2.1},
    {0.34, -0.19, 4.1, 0.025, 0.31, 4.0},
    {0.09, 0.41, 2.6, 0.045, 0.25, 1.1},
    {-0.47, -0.12, 5.3, -0.065, 0.17, 5.2}
  ]
  @amps @waves |> Enum.map(&elem(&1, 4)) |> List.to_tuple()

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    # Half the frame, in ems.
    hx = @cols / 2 * @cw
    hy = @rows / 2 * @rh

    # The hill falls to nothing at the frame's edges, so every line closes
    # inside it. What does not move at each corner of the cells: each swell's
    # argument before its drift, and the hill's envelope.
    points =
      for r <- 0..@rows do
        y = (r - @rows / 2) * @rh

        List.to_tuple(
          for c <- 0..@cols do
            x = (c - @cols / 2) * @cw
            args = @waves |> Enum.map(fn {kx, ky, p, _, _, _} -> kx * x + ky * y + p end)
            qx = x / 17
            qy = y / 8
            rx = x / hx
            ry = y / hy
            envelope = :math.exp(-(qx * qx) - qy * qy) * (1 - rx * rx) * (1 - ry * ry)
            {List.to_tuple(args), envelope}
          end
        )
      end

    %{points: List.to_tuple(points)}
  end

  @impl true
  def frame(state, t, _env) do
    turn = 2 * :math.pi() * t / @period

    phases =
      @waves
      |> Enum.map(fn {_, _, _, w, _, psi} ->
        w * @start + JSMath.sign(w) * @swing * :math.sin(turn + psi)
      end)
      |> List.to_tuple()

    h = state.points |> Tuple.to_list() |> Enum.map(&heights(&1, phases)) |> List.to_tuple()
    cells = cells(h)
    sea = sea(cells)
    lvl = cells |> Enum.map(&elem(&1, 3)) |> List.to_tuple()
    dot = dots(cells, sea)
    cells = List.to_tuple(cells)
    off = fn i -> elem(elem(cells, i), 4) end
    doff = fn i -> elem(elem(cells, i), 5) end
    keep = thin(lvl, off, cells)
    dots = thin(dot, doff, cells)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          i = r * @cols + c

          cond do
            MapSet.member?(keep, i) -> stroke(cells, keep, lvl, i, c)
            MapSet.member?(dots, i) -> "·"
            true -> " "
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # The swells never cut the hill below @floor, so the coast keeps no deep
  # inlets.
  defp heights(row, {p0, p1, p2, p3, p4}) do
    {a0, a1, a2, a3, a4} = @amps

    row
    |> Tuple.to_list()
    |> Enum.map(fn {{b0, b1, b2, b3, b4}, envelope} ->
      n = 1 + a0 * :math.sin(b0 + p0)
      n = n + a1 * :math.sin(b1 + p1)
      n = n + a2 * :math.sin(b2 + p2)
      n = n + a3 * :math.sin(b3 + p3)
      n = n + a4 * :math.sin(b4 + p4)
      n = @floor + JSMath.log1p(:math.exp(6 * (n - @floor))) / 6
      envelope * n
    end)
    |> List.to_tuple()
  end

  # Each cell: its mean height, its slope, the line it draws (0 for none) and
  # how far its centre is from that line, in ems; then the same for the
  # dotted line offshore; and whether the line runs steeper than a cell's
  # diagonal.
  defp cells(h) do
    for r <- 0..(@rows - 1), top = elem(h, r), bottom = elem(h, r + 1), c <- 0..(@cols - 1) do
      a = elem(top, c)
      b = elem(top, c + 1)
      d = elem(bottom, c)
      e = elem(bottom, c + 1)
      mid = (a + b + d + e) / 4
      gx = (b + e - a - d) / (2 * @cw)
      gy = (d + e - a - b) / (2 * @rh)
      lo = a |> min(b) |> min(d) |> min(e)
      hi = a |> max(b) |> max(d) |> max(e)
      g = JSMath.hypot(gx, gy)
      g = if g == 0, do: 1.0e-9, else: g
      l = JSMath.round(mid / @level)

      # Where lines crowd together, every other one gives way; the coast
      # never does.
      {lvl, off} =
        if l >= 1 and lo < l * @level and hi >= l * @level and
             (@level / g > @crowd or rem(l, 2) == 1),
           do: {l, abs(l * @level - mid) / g},
           else: {0, nil}

      {dot, doff} =
        if lo < @level / 2 and hi >= @level / 2,
          do: {1, abs(@level / 2 - mid) / g},
          else: {0, nil}

      {mid, gx, gy, lvl, off, doff, dot, abs(gx) * @cw > abs(gy) * @rh}
    end
  end

  @compile {:inline, neighbours: 1}
  defp neighbours(i) do
    r = div(i, @cols)
    c = rem(i, @cols)

    [
      if(c > 0, do: i - 1, else: -1),
      if(c < @cols - 1, do: i + 1, else: -1),
      if(r > 0, do: i - @cols, else: -1),
      if(r < @rows - 1, do: i + @cols, else: -1)
    ]
  end

  # The sea is the low ground reached from the frame's edge; a hollow inland
  # is not.
  defp sea(cells) do
    low = cells |> Enum.map(&(elem(&1, 0) < @level / 2)) |> List.to_tuple()

    seeds =
      for i <- 0..(@n - 1),
          r = div(i, @cols),
          c = rem(i, @cols),
          r == 0 or c == 0 or r == @rows - 1 or c == @cols - 1,
          elem(low, i),
          do: i

    flood(seeds, MapSet.new(seeds), low)
  end

  defp flood([], sea, _low), do: sea

  defp flood([i | stack], sea, low) do
    {stack, sea} =
      Enum.reduce(neighbours(i), {stack, sea}, fn j, {stack, sea} ->
        if j >= 0 and not MapSet.member?(sea, j) and elem(low, j),
          do: {[j | stack], MapSet.put(sea, j)},
          else: {stack, sea}
      end)

    flood(stack, sea, low)
  end

  # The dotted line runs only along the open sea, not round a hollow inland.
  defp dots(cells, sea) do
    cells
    |> Enum.with_index()
    |> Enum.map(fn {cell, i} ->
      if elem(cell, 6) == 1 and
           (MapSet.member?(sea, i) or
              Enum.any?(neighbours(i), &(&1 >= 0 and MapSet.member?(sea, &1)))),
         do: 1,
         else: 0
    end)
    |> List.to_tuple()
  end

  # Each line keeps only the cell nearest it across its own stroke: one per
  # row where it runs steep, one per column where it runs flat. Then pieces
  # too short to read as a line are dropped.
  defp thin(lv, of, cells) do
    kept =
      for i <- 0..(@n - 1), l = elem(lv, i), l != 0, nearest?(lv, of, cells, i, l), do: i

    keep = MapSet.new(kept)

    {keep, _} =
      Enum.reduce(kept, {keep, MapSet.new()}, fn i, {keep, seen} ->
        if MapSet.member?(seen, i) do
          {keep, seen}
        else
          {part, seen} = part([i], [i], MapSet.put(seen, i), keep, lv, elem(lv, i))

          if length(part) < @speck,
            do: {MapSet.difference(keep, MapSet.new(part)), seen},
            else: {keep, seen}
        end
      end)

    keep
  end

  defp nearest?(lv, of, cells, i, l) do
    r = div(i, @cols)
    c = rem(i, @cols)

    {p, q} =
      if elem(elem(cells, i), 7),
        do: {if(c > 0, do: i - 1, else: -1), if(c < @cols - 1, do: i + 1, else: -1)},
        else: {if(r > 0, do: i - @cols, else: -1), if(r < @rows - 1, do: i + @cols, else: -1)}

    oi = of.(i)

    beaten = fn j ->
      j >= 0 and elem(lv, j) == l and (of.(j) < oi or (of.(j) == oi and j < i))
    end

    not beaten.(p) and not beaten.(q)
  end

  # A piece of line: the kept cells of its level that touch, corners too.
  defp part([], part, seen, _keep, _lv, _l), do: {part, seen}

  defp part([i | queue], part, seen, keep, lv, l) do
    r = div(i, @cols)
    c = rem(i, @cols)

    {queue, part, seen} =
      for dr <- -1..1,
          dc <- -1..1,
          rr = r + dr,
          cc = c + dc,
          rr >= 0 and rr < @rows and cc >= 0 and cc < @cols,
          j = rr * @cols + cc,
          MapSet.member?(keep, j) and not MapSet.member?(seen, j) and elem(lv, j) == l,
          reduce: {queue, part, seen} do
        {queue, part, seen} -> {queue ++ [j], [j | part], MapSet.put(seen, j)}
      end

    part(queue, part, seen, keep, lv, l)
  end

  defp stroke(cells, keep, lvl, i, c) do
    {mid, gx, gy, l, off, _doff, _dot, _steep} = elem(cells, i)
    # The line, off horizontal.
    angle = :math.atan2(abs(gx), abs(gy)) * (180 / :math.pi())
    # Where the line crosses the cell, 0 at its top to 1 at its bottom.
    y = 0.5 + (l * @level - mid) / (if(gy == 0, do: 1.0e-9, else: gy) * @rh)

    # A slash beside a nearer slash of the same line becomes the flat step
    # between them.
    twin = fn j ->
      j >= 0 and MapSet.member?(keep, j) and elem(lvl, j) == l and
        elem(elem(cells, j), 4) < off
    end

    paired =
      angle > 45 and angle <= 63 and
        (twin.(if(c > 0, do: i - 1, else: -1)) or twin.(if(c < @cols - 1, do: i + 1, else: -1)))

    glyph(angle, y, paired, gx * gy > 0)
  end

  defp glyph(angle, _y, _paired, _rising) when angle > 76, do: "|"

  defp glyph(angle, y, paired, rising)
       when angle > 45 and not (paired and (y < 0.35 or y > 0.65)),
       do: slash(rising)

  defp glyph(angle, y, false, _rising) when angle < 10, do: if(y < 0.6, do: "-", else: "_")
  defp glyph(_angle, y, _paired, _rising) when y < 0.3, do: "'"
  defp glyph(_angle, y, _paired, _rising) when y < 0.6, do: "-"
  defp glyph(_angle, y, _paired, _rising) when y < 0.85, do: "."
  defp glyph(_angle, _y, _paired, _rising), do: "_"

  defp slash(true), do: "/"
  defp slash(false), do: "\\"
end
