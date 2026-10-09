defmodule Ascii.Pieces.SeaSwell do
  @moduledoc """
  A long swell lifting a small sailboat as it rolls under.

  A long ocean swell seen side on, a rounded crest over a long flat trough.
  A sailboat rides it, pitching with the slope under its hull, while the
  crests hide and show the far horizon.

  Ported from `src/pieces/sea-swell.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}

  @meta %Ascii.Meta{
    name: "sea swell",
    category: :nature,
    note: "a long swell lifting a small sailboat as it rolls under",
    cols: 64,
    rows: 14,
    fps: 20,
    loop: 16
  }

  @cols 64
  @rows 14
  @tau :math.pi() * 2
  # The row of the far sea, and the still water line, in rows from the top.
  @horizon 4
  @mean 6.1
  # The line's glyph by where it crosses its cell, bottom to top.
  @surf {"_", ".", "-", "'"}
  # The boat level, bow up on the right, and bow up on the left. Row 0 is the
  # hull's bottom, which sits on the water; the mast stands in column 3.
  @level ["   |\\", "   | \\", "   |__\\", "\\________/"]
  @right ["   |\\", "   | \\", "   |__\\ _/", "\\____.-'"]
  @left ["   |\\", "   | \\", "\\_ |__\\", "  '-.____/"]
  # The hull's length in columns; rows the water rises along the hull before
  # the boat pitches to it; column of the boat's left end.
  @hull 10
  @pitch 0.55
  @boat_x 18
  # Each wave: {length in columns, waves a second, trough to crest in rows,
  # crest sharpness}. The second runs back against the first, so the crests
  # rise and fall in height; both come back round every 16 seconds.
  @swell {64, 0.0625, 3.8, 0.5}
  @chop {32, -0.0625, 0.9, 0.3}
  # How far the swell's crest runs ahead of its trough, in columns; seconds
  # into the loop where t = 0 falls (the boat on the rising face); the
  # swell's wavenumber in rows, so the motion dies away with depth.
  @lean 2
  @start 2.5
  @k @tau / 32

  @impl true
  def meta, do: @meta

  # One trochoid, -0.5 in the trough to 0.5 on the crest.
  defp trochoid(u, q) do
    v = Enum.reduce(1..4, u, fn _, v -> u + q / @tau * :math.sin(@tau * v) end)
    0.5 * :math.cos(@tau * v)
  end

  @impl true
  def init(_options) do
    rand = Int32.to_int32(21)

    # Ripples in the water as {column, depth below the surface, glyph}: short
    # runs near the top, fewer and finer the deeper they lie. A few more lie
    # on the far sea under the horizon.
    {flecks, rand} =
      Enum.flat_map_reduce(0..8, rand, fn j, rand ->
        d = 1.5 + j

        glyph =
          cond do
            d < 3 -> "~"
            d < 5.5 -> "-"
            true -> "·"
          end

        run =
          cond do
            d < 3 -> 3
            d < 5.5 -> 2
            true -> 1
          end

        {from, rand} = Int32.mulberry32(rand)
        {cells, rand} = flecks(0, floor(from * @cols), 3 + d * 2, run, rand, [])
        {for(i <- cells, do: {rem(i, @cols), :math.exp(-@k * d), d, glyph}), rand}
      end)

    {far, _} =
      Enum.flat_map_reduce((@horizon + 1)..(@horizon + 3), rand, fn r, rand ->
        {first, rand} = Int32.mulberry32(rand)
        far(r, floor(first * 12), rand, [])
      end)

    %{flecks: flecks, far: far}
  end

  defp flecks(i, _from, _gap, run, rand, acc) when i >= @cols - run, do: {Enum.reverse(acc), rand}

  defp flecks(i, from, gap, run, rand, acc) do
    {r, rand} = Int32.mulberry32(rand)
    n = 1 + floor(r * run)
    acc = Enum.reduce(0..(n - 1), acc, fn k, acc -> [from + i + k | acc] end)
    {step, rand} = Int32.mulberry32(rand)
    flecks(i + n + floor(gap * (0.6 + step)), from, gap, run, rand, acc)
  end

  defp far(_r, c, rand, acc) when c >= @cols, do: {Enum.reverse(acc), rand}

  defp far(r, c, rand, acc) do
    {s, rand} = Int32.mulberry32(rand)
    {step, rand} = Int32.mulberry32(rand)
    far(r, c + 11 + floor(step * 14), rand, [{r, c, if(s < 0.5, do: 1, else: 2)} | acc])
  end

  # The surface in rows from the top at column edge x, the swell's crest
  # sheared forward so its front face is the steeper one.
  defp surface(x, t) do
    {l, v, a, q} = @swell
    h = trochoid(x / l - t * v, q)
    h = Enum.reduce(1..3, h, fn _, h -> trochoid((x - @lean * (h + 0.5)) / l - t * v, q) end)
    {l2, v2, a2, q2} = @chop
    @mean - a * h - a2 * trochoid(x / l2 - t * v2, q2)
  end

  @impl true
  def frame(state, time, _env) do
    t = time + @start
    sy = List.to_tuple(for x <- 0..@cols, do: surface(x, t))
    # The surface's row.
    top = List.to_tuple(for c <- 0..(@cols - 1), do: floor((elem(sy, c) + elem(sy, c + 1)) / 2))

    # The far sea shows only over the near trough, stopping a cell short of
    # it.
    clear = fn c ->
      c < 0 or c >= @cols or @horizon < min(elem(sy, c), elem(sy, c + 1)) - 0.9
    end

    g =
      for c <- 0..(@cols - 1), clear.(c - 1) and clear.(c) and clear.(c + 1), into: %{} do
        {{@horizon, c}, "_"}
      end

    g =
      for {r, c, n} <- state.far,
          k <- 0..(n - 1),
          c + k < @cols and Map.get(g, {@horizon, c + k}) == "_" and r < elem(top, c + k) - 1,
          reduce: g do
        g -> Map.put(g, {r, c + k}, "-")
      end

    # The near water: flecks ride the swell, less the deeper they lie.
    g =
      for {c, fade, d, ch} <- state.flecks,
          y = elem(sy, c) * 0.5 + elem(sy, c + 1) * 0.5,
          r = floor(@mean + (y - @mean) * fade + d),
          r > elem(top, c) and r < @rows,
          reduce: g do
        g -> Map.put(g, {r, c}, ch)
      end

    g =
      for c <- 0..(@cols - 1), reduce: g do
        g ->
          a = elem(sy, c)
          b = elem(sy, c + 1)
          y = (a + b) / 2
          r = floor(y)

          ch =
            cond do
              abs(b - a) > 0.8 and b < a -> "/"
              abs(b - a) > 0.8 -> "\\"
              true -> elem(@surf, min(3, floor((1 - (y - r)) * 4)))
            end

          Map.put(g, {r, c}, ch)
      end

    g = boat(g, t, top)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(g, {r, c}, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # The boat surges a little with the water, forward on the crests and back
  # in the troughs, and pitches to the slope along its hull.
  defp boat(g, t, top) do
    {l, v, _, _} = @swell
    c0 = JSMath.round(@boat_x - 1.5 * :math.sin(@tau * ((@boat_x + @hull / 2) / l - t * v)))
    rise = surface(c0 + 1, t) - surface(c0 + @hull - 1, t)

    {shape, at} =
      cond do
        rise > @pitch -> {@right, c0 + 2.5}
        rise < -@pitch -> {@left, c0 + @hull - 2.5}
        true -> {@level, c0 + @hull / 2}
      end

    water = floor(surface(at, t))

    # The hull takes the place of the water line under it, with a cell clear
    # at either end, and the horizon stands back from the whole boat.
    g =
      for c <- (c0 - 3)..(c0 + @hull + 2), c >= 0 and c < @cols, reduce: g do
        g ->
          g =
            if elem(top, c) != @horizon and water - @horizon <= 4,
              do: Map.put(g, {@horizon, c}, " "),
              else: g

          if c >= c0 - 1 and c <= c0 + @hull do
            for r <- (water - 4)..max(water, elem(top, c))//1, r >= 0, reduce: g do
              g -> Map.put(g, {r, c}, " ")
            end
          else
            g
          end
      end

    n = length(shape)

    for {line, i} <- Enum.with_index(shape),
        r = water - n + 1 + i,
        r >= 0,
        {ch, k} <- Enum.with_index(String.codepoints(line)),
        ch != " ",
        reduce: g do
      g -> Map.put(g, {r, c0 + k}, ch)
    end
  end
end
