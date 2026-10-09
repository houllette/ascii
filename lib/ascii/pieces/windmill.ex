defmodule Ascii.Pieces.Windmill do
  @moduledoc """
  Four lattice sails turning on a dutch mill, clouds passing.

  A Dutch smock mill on a low rise, its four lattice sails turning in front
  of the cap, a stage round its waist and clouds drifting behind.

  Ported from `src/pieces/windmill.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Hash

  @meta %Ascii.Meta{
    name: "windmill",
    category: :objects,
    note: "four lattice sails turning on a dutch mill, clouds passing",
    cols: 64,
    rows: 28,
    fps: 20
  }

  @cols 64
  @rows 28
  @n 64 * 28
  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @fluff {" ", ".", "·", ":", "-"}
  # The hub, column and row.
  @hx 32
  @hy 11.5
  # A sail's reach from the hub, in rows; the lattice's width; between the
  # laths; where the lattice starts along the stock.
  @sail 10.8
  @width 3
  @lath 2.25
  @foot 1.8
  # Seconds a turn.
  @period 9
  # The body's rows; its half width at the top and foot, in rows; the row of
  # the stage round its waist.
  @top 12
  @ground 24.5
  @wt 3.6
  @wb 5.6
  @stage 18
  # Clouds: puffs as {x, y, radius} about an origin; row, speed in columns a
  # second, start.
  @clouds [
    {[{0, 0, 1.6}, {2.2, -0.9, 2.3}, {4.7, -0.4, 2}, {6.7, 0.2, 1.4}], 4.4, 1.1, 26},
    {[{0, 0, 1.3}, {1.8, -0.6, 1.7}, {3.5, 0, 1.3}], 2.4, 0.7, 64},
    {[{0, 0, 1.4}, {2, -0.8, 2}, {4.1, -0.5, 1.7}, {5.8, 0.2, 1.2}], 17.4, 1.5, 84}
  ]

  @impl true
  def meta, do: @meta

  defp hash(x, y), do: Hash.short(x, y)

  # The one glyph a straight stroke at this heading is drawn in: "/" and "\"
  # climb a row a column, so a line much flatter than a row every two
  # columns runs as "-".
  defp stroke(a) do
    d = JSMath.mod(JSMath.mod(a * 180 / :math.pi(), 180) + 180, 180)

    cond do
      d < 40 or d >= 140 -> "-"
      d < 76.7 -> "/"
      d < 103.3 -> "|"
      true -> "\\"
    end
  end

  @impl true
  def init(_options) do
    # The mill itself does not change: the body, cap, stage and the land.
    still =
      for r <- 0..(@rows - 1), c <- 0..(@cols - 1), reduce: %{} do
        still ->
          case still_cell(r, c) do
            nil -> still
            v -> Map.put(still, r * @cols + c, v)
          end
      end
      |> stage()

    base = fn paper ->
      List.to_tuple(
        for k <- 0..(@n - 1) do
          case Map.get(still, k) do
            v when is_number(v) ->
              i = max(1, min(9, JSMath.round(v * 9)))
              elem(@ramp, if(paper, do: 10 - i, else: i))

            v ->
              v
          end
        end
      )
    end

    # The cells the sails can reach.
    reach = (@sail + 1) * (@sail + 1)

    sweep =
      for r <- 0..(@rows - 1),
          c <- 0..(@cols - 1),
          x = (c - @hx) / 2,
          y = @hy - (r + 0.5),
          x * x + y * y <= reach,
          do: {r * @cols + c, x, y}

    %{base: {base.(false), base.(true)}, sweep: sweep}
  end

  defp still_cell(r, c) do
    x = (c + 0.5 - @hx) / 2
    y = r + 0.5
    g = @ground

    cond do
      # The land: a level line, and grass thinning toward us.
      r == floor(g) ->
        if hash(c, 9) < 0.12, do: ",", else: "_"

      r > g ->
        grass(hash(c, r), r - g + 0.5)

      true ->
        body(r, x, y) || cap(x, y)
    end
  end

  defp grass(h, d) do
    cond do
      h < 0.2 / d -> ","
      h < 0.32 / d -> "'"
      h < 0.4 / d -> "."
      true -> " "
    end
  end

  # The body: three faces of an octagon in boards, lit from the left.
  defp body(r, x, y) when y > @top and y < @ground do
    w = @wt + (@wb - @wt) * (y - @top) / (@ground - @top)

    if abs(x) < w do
      u = x / w

      v =
        cond do
          u < -0.4 -> 0.8
          u < 0.4 -> 0.55
          true -> 0.3
        end

      v = if rem(r, 2) != 0, do: v - 0.08, else: v

      cond do
        # The door.
        abs(x) < 0.8 and y > @ground - 2.2 -> 0.08
        # Windows.
        abs(x + 0.2) < 0.4 and (r == @top + 2 or r == @stage + 2) -> 0.08
        true -> v
      end
    end
  end

  defp body(_r, _x, _y), do: nil

  # The cap: a rounded hood over the top, lit from the upper left.
  defp cap(x, y) do
    q = JSMath.hypot(x / (@wt + 0.6), (y - @top - 0.2) / 3.8)

    if y <= @top + 0.5 and q < 1 do
      nx = x / (@wt + 0.6)
      ny = (@top + 0.2 - y) / 3.8
      nz = :math.sqrt(max(0, 1 - q * q))
      0.15 + 0.75 * max(0, -0.5 * nx + 0.5 * ny + 0.7 * nz)
    end
  end

  # The stage: a deck on struts, a rail along it.
  defp stage(still) do
    sw = @wt + (@wb - @wt) * (@stage - @top) / (@ground - @top) + 1.8
    c0 = JSMath.round(@hx - 2 * sw)
    c1 = JSMath.round(@hx + 2 * sw)

    still =
      Enum.reduce(c0..c1, still, fn c, still ->
        still
        |> Map.put(@stage * @cols + c, "=")
        |> Map.put((@stage - 1) * @cols + c, if(rem(c - @hx, 2) == 0, do: "|", else: "_"))
      end)

    still
    |> Map.put((@stage + 1) * @cols + c0 + 1, "\\")
    |> Map.put((@stage + 1) * @cols + c1 - 1, "/")
  end

  @impl true
  def frame(state, t, env) do
    base = elem(state.base, if(env.paper, do: 1, else: 0))
    sky = clouds(t)
    sails = sails(state.sweep, t)

    hub = floor(@hy) * @cols + @hx
    sails = sails |> Map.put(hub - 1, "(") |> Map.put(hub, "@") |> Map.put(hub + 1, ")")

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          k = r * @cols + c
          Map.get(sails, k) || elem(base, k) || Map.get(sky, k, " ")
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # The clouds: how much of each cell they cover, eight looks a cell, and how
  # lit they are there, as heaps of round puffs lit from above with flat
  # undersides. Soft, brightest along their tops, a thin rim where they thin
  # out.
  defp clouds(t) do
    @clouds
    |> Enum.reduce(%{}, &cloud(&1, &2, t))
    |> Enum.reduce(%{}, fn {k, {n, shade}}, sky ->
      f = n / 8

      if f < 0.2 do
        sky
      else
        v = f * (0.3 + 0.4 * shade)
        Map.put(sky, k, elem(@fluff, max(1, min(4, JSMath.round(v * 5.5)))))
      end
    end)
  end

  defp cloud({puffs, row, speed, start}, acc, t) do
    span = @cols + 36
    ox = JSMath.mod(JSMath.mod(start + speed * t, span) + span, span) - 22

    for r <- floor(row - 4)..floor(row + 1)//1,
        c <- Stream.iterate(floor(ox - 6), &(&1 + 1)) |> Enum.take_while(&(&1 < ox + 22)),
        r >= 0 and r < @rows and c >= 0 and c < @cols,
        j <- 0..3,
        i <- 0..1,
        reduce: acc do
      acc ->
        px = (c + 0.25 + i * 0.5 - ox) / 2
        py = r + 0.125 + j * 0.25 - row

        # Below the flat undersides there is nothing to see.
        lit = if py > 0.8, do: -1, else: lit(puffs, px, py)

        if lit < -0.5 do
          acc
        else
          Map.update(acc, r * @cols + c, {1, JSMath.fround(max(0, lit))}, fn {n, shade} ->
            {n + 1, JSMath.fround(max(shade, lit))}
          end)
        end
    end
  end

  defp lit(puffs, px, py) do
    Enum.reduce(puffs, -1, fn {a, b, rad}, lit ->
      nx = (px - a) / rad
      ny = (py - b) / rad
      q = nx * nx + ny * ny
      if q < 1, do: max(lit, -0.3 * nx - 0.8 * ny + 0.5 * :math.sqrt(1 - q)), else: lit
    end)
  end

  # The sails: for each, a stock from the hub and a ladder of laths on its
  # trailing side, over a light fill of the lattice so it reads as a blade.
  defp sails(sweep, t) do
    # Square to the frame at the start.
    turn = 2 * :math.pi() * t / @period

    sails =
      for i <- 0..3 do
        a = turn + i * :math.pi() / 2
        ax = :math.cos(a)
        ay = :math.sin(a)
        # A line takes one cell a row where it runs steep, one a column where it runs flat.
        reach_v = if abs(ay) > 2 * abs(ax), do: 0.25 * abs(ay), else: 0.5 * abs(ax)
        reach_u = if abs(ax) > 2 * abs(ay), do: 0.25 * abs(ax), else: 0.5 * abs(ay)
        {ax, ay, reach_v, reach_u, stroke(a), stroke(a + :math.pi() / 2)}
      end

    Enum.reduce(sweep, %{}, fn {k, x, y}, out ->
      {hit, _rank} =
        Enum.reduce(sails, {nil, 0}, fn sail, {hit, rank} ->
          case blade(sail, x, y) do
            {ch, rk} when rk > rank -> {ch, rk}
            _ -> {hit, rank}
          end
        end)

      if hit, do: Map.put(out, k, hit), else: out
    end)
  end

  # On a line where the cell is as near one side as the other, the small bias picks one.
  defp on?(d, reach), do: abs(d + 0.013) <= reach

  # What one sail draws in a cell, and its rank: stock, edge, lath, fill.
  defp blade({ax, ay, reach_v, reach_u, edge, lath}, x, y) do
    # Along the stock, and across to the lattice.
    u = x * ax + y * ay
    v = x * ay - y * ax

    cond do
      u < 0.6 or u > @sail + 0.6 or v < -0.8 or v > @width + 0.8 ->
        nil

      on?(v, reach_v) and u < @sail + 0.3 ->
        {"#", 4}

      u > @foot - 0.2 and u < @sail + 0.3 and on?(v - @width, reach_v) ->
        {edge, 3}

      v > 0.45 and v < @width - 0.45 and u > @foot - 0.5 and u < @sail + 0.3 and
          on?(JSMath.mod(u - @foot + @lath / 2, @lath) - @lath / 2, reach_u) ->
        {lath, 2}

      true ->
        fill(ax, ay, x, y)
    end
  end

  # How much of the cell the lattice covers, from eight looks.
  defp fill(ax, ay, x, y) do
    n =
      for j <- 0..3, i <- 0..1, reduce: 0 do
        n ->
          px = x + (i - 0.5) * 0.25
          py = y - (j - 1.5) * 0.25
          uu = px * ax + py * ay
          vv = px * ay - py * ax
          if uu > @foot and uu < @sail and vv > 0 and vv < @width, do: n + 1, else: n
      end

    if n >= 4, do: {".", 1}
  end
end
