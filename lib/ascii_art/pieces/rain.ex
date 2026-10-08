defmodule AsciiArt.Pieces.Rain do
  @moduledoc """
  Slanting rain in three depths, crowns and puddle rings.

  Slanting rain in three depths over open ground. Each drop ends where it
  meets the ground at its own depth, throwing up a crown on the ground or
  opening a ring where it falls in a puddle.

  Ported from `src/pieces/rain.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "rain",
    category: :nature,
    note: "slanting rain in three depths, crowns and puddle rings",
    cols: 64,
    rows: 20,
    fps: 30
  }

  @cols 64
  @rows 20
  # The far edge of the ground.
  @horizon 11
  # Each depth, far to near: drops, rows a second, streak length, the rows it
  # lands between, and its glyph.
  @layers [
    %{n: 46, v: 11, len: 1, from: 12, to: 13.9, glyph: ","},
    %{n: 30, v: 19, len: 2, from: 14, to: 16.9, glyph: "/"},
    %{n: 16, v: 30, len: 4, from: 17, to: 19.9, glyph: "╱"}
  ]
  # Puddles, flat ovals in perspective: middle column and row, half width in
  # columns, half height in rows.
  @puddles [{45, 13.5, 6, 0.7}, {17, 15.5, 10, 1.6}, {44, 18.5, 14, 1.6}]
  # How long a ring on the water lasts, by depth.
  @lives {0.35, 0.6, 0.85}

  @impl true
  def meta, do: @meta

  defp hash(i, s) do
    h =
      bxor(
        Int32.umul(bxor(Int32.u32(i), 0x9E3779B9), 0x85EBCA6B),
        Int32.umul(Int32.u32(s + 1), 0xC2B2AE35)
      )

    h = Int32.umul(bxor(h, bsr(h, 15)), 0x2C1B3C6D)
    h = Int32.umul(bxor(h, bsr(h, 12)), 0x297A2D39)
    bxor(h, bsr(h, 15)) / 4_294_967_296
  end

  @impl true
  def init(_options) do
    # The ground: a horizon, a scatter of grit that grows coarser nearer, and
    # each puddle as a sheet of still water with a ragged edge.
    pool =
      for {{cx, cy, rx, ry}, p} <- Enum.with_index(@puddles),
          r <- floor(cy - ry)..floor(cy + ry),
          v = (r + 0.5 - cy) / ry,
          abs(v) < 1,
          w = rx * :math.sqrt(1 - v * v),
          a = JSMath.round(cx - w + (hash(r, p + 20) - 0.5) * 2.5),
          b = JSMath.round(cx + w + (hash(r, p + 30) - 0.5) * 2.5),
          c <- max(0, a)..(min(@cols, b) - 1)//1,
          reduce: %{} do
        pool -> Map.put(pool, {r, c}, p)
      end

    base =
      for r <- 0..(@rows - 1) do
        List.to_tuple(for c <- 0..(@cols - 1), do: ground(pool, r, c))
      end

    pool =
      for r <- 0..(@rows - 1) do
        List.to_tuple(for c <- 0..(@cols - 1), do: Map.get(pool, {r, c}, -1))
      end

    %{base: List.to_tuple(base), pool: List.to_tuple(pool)}
  end

  defp ground(_pool, @horizon, _c), do: "_"

  defp ground(pool, r, c) do
    cond do
      Map.has_key?(pool, {r, c}) ->
        "─"

      r > @horizon ->
        h = hash(r * @cols + c, 3)
        near = (r - @horizon) / (@rows - @horizon)

        cond do
          h >= 0.035 or wet?(pool, r, c) -> " "
          near > 0.5 and h < 0.012 -> "`"
          true -> "."
        end

      true ->
        " "
    end
  end

  defp wet?(pool, r, c) do
    Enum.any?(-1..1, fn d ->
      Map.has_key?(pool, {r, c + d}) or Map.has_key?(pool, {r - 1, c + d}) or
        Map.has_key?(pool, {r + 1, c + d})
    end)
  end

  # The puddle a cell lies in, -1 for none or for a cell off the grid (which
  # upstream reads as undefined, never equal to a puddle).
  defp pool(pool, r, c) when r >= 0 and r < @rows and c >= 0 and c < @cols,
    do: elem(elem(pool, r), c)

  defp pool(_pool, _r, _c), do: -1

  @impl true
  def frame(state, t, _env) do
    {g, splashes} =
      @layers
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {l, li}, acc -> layer(acc, l, li, t, state.pool) end)

    g =
      splashes
      |> Enum.reverse()
      |> Enum.reduce(g, &splash(&1, &2, state.pool))

    lines =
      for r <- 0..(@rows - 1) do
        row = elem(state.base, r)
        for c <- 0..(@cols - 1), do: Map.get(g, {r, c}, elem(row, c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp layer({g, splashes}, l, li, t, pool) do
    cycle = (l.to + l.len) / l.v + 0.6

    Enum.reduce(0..(l.n - 1), {g, splashes}, fn i, {g, splashes} ->
      tt = t + hash(i, li * 3) * cycle
      k = floor(tt / cycle)
      u = tt - k * cycle
      id = i * 977 + k * 13 + li
      # Where this drop lands: its depth sets the row.
      land = floor(l.from + (l.to - l.from) * hash(id, 1))
      lx = floor(hash(id, 2) * (@cols + 2)) - 1
      head = -l.len + l.v * u

      if head < land do
        # The streak runs up and to the right of its head, a column a row,
        # and passes behind the horizon and the water's edge.
        g =
          for j <- 0..(l.len - 1),
              r = floor(head) - j,
              c = lx + (land - r),
              r >= 0 and r < land and c >= 0 and c < @cols and r != @horizon and
                pool(pool, r, c) < 0,
              reduce: g do
            g -> Map.put(g, {r, c}, l.glyph)
          end

        {g, splashes}
      else
        {g, [{lx, land, (head - land) / l.v, li} | splashes]}
      end
    end)
  end

  defp splash({x, _y, _age, _li}, g, _pool) when x < 0 or x >= @cols, do: g

  defp splash({x, y, age, li}, g, pool) do
    p = pool(pool, y, x)
    if p >= 0, do: ring(g, pool, p, x, y, age, li), else: crown(g, pool, x, y, age, li)
  end

  # A ring on the water: a bead, then two marks walking apart and fading.
  defp ring(g, pool, p, x, y, age, li) do
    life = elem(@lives, li)
    d = floor(age / life * (2 + 3 * li))
    mark = if age > life * 0.7, do: "·"

    cond do
      age > life ->
        g

      d == 0 ->
        put(g, x, y, "o")

      pool(pool, y, x - d) == p and pool(pool, y, x + d) == p ->
        g |> put(x - d, y, mark || "(") |> put(x + d, y, mark || ")")

      true ->
        g
    end
  end

  # On the ground: far drops just bead; nearer ones throw up a crown that
  # breaks into drops falling back either side.
  defp crown(g, pool, x, y, age, 0), do: if(age < 0.1, do: spray(g, pool, x, y, "."), else: g)

  defp crown(g, pool, x, y, age, 1) do
    cond do
      age < 0.08 -> spray(g, pool, x, y, "v")
      age < 0.22 -> g |> spray(pool, x - 1, y, ".") |> spray(pool, x + 1, y, ".")
      true -> g
    end
  end

  defp crown(g, pool, x, y, age, _li) do
    cond do
      age < 0.09 ->
        g
        |> spray(pool, x - 1, y - 1, "\\")
        |> spray(pool, x, y - 1, "|")
        |> spray(pool, x + 1, y - 1, "/")
        |> spray(pool, x, y, ".")

      age < 0.2 ->
        g |> spray(pool, x - 2, y - 1, "'") |> spray(pool, x + 2, y - 1, "'")

      age < 0.32 ->
        g |> spray(pool, x - 2, y, ".") |> spray(pool, x + 2, y, ".")

      true ->
        g
    end
  end

  defp put(g, c, r, ch) when r >= 0 and r < @rows and c >= 0 and c < @cols,
    do: Map.put(g, {r, c}, ch)

  defp put(g, _c, _r, _ch), do: g

  # Spray lands on open ground only, never in the water or on the horizon.
  defp spray(g, pool, c, r, ch) do
    if r > @horizon and r < @rows and c >= 0 and c < @cols and pool(pool, r, c) < 0,
      do: Map.put(g, {r, c}, ch),
      else: g
  end
end
