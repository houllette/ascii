defmodule AsciiArt.Pieces.Lightning do
  @moduledoc """
  A forked bolt striking out of a storm cloud in the rain.

  A storm over low hills in driving rain. Every few seconds a bolt zigzags
  down from the cloud to the ground, forks as it strikes, flickers through a
  restrike, lights the cloud and the land, and fades.

  Ported from `src/pieces/lightning.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Hash

  @meta %AsciiArt.Meta{
    name: "lightning",
    category: :nature,
    note: "a forked bolt striking out of a storm cloud in the rain",
    cols: 64,
    rows: 22,
    fps: 20
  }

  @cols 64
  @rows 22
  # Cloud, thin to thick. A flash is light, not shade, so it keeps its sense
  # on paper.
  @cloud {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # The cloud's underside by where it crosses a cell, top to bottom.
  @edge {"'", "-", ".", "_"}
  @skyline {"_", ".", "-", "'"}
  # Seconds.
  @loop 12
  # Strikes: {start within the loop, column the bolt leaves the cloud}.
  @strikes [{11.94, 27}, {2.44, 44}, {4.62, 17}, {7.6, 51}, {9.9, 34}]
  # The row the cloud's flat base sits on, where no billow hangs; columns a
  # second the billows drift.
  @deck 2.6
  @drift 0.35
  @drops 130
  @wrap 64 + 24
  @splash [{-2, "-"}, {-1, "\\"}, {0, "*"}, {1, "/"}, {2, "-"}]

  @impl true
  def meta, do: @meta

  @compile {:inline, ease: 1}
  defp ease(t), do: t * t * (3 - 2 * t)

  defp noise(x, y) do
    i = floor(x)
    j = floor(y)
    u = ease(x - i)
    v = ease(y - j)
    a = Hash.murmur(i, j)
    b = Hash.murmur(i + 1, j)
    c = Hash.murmur(i, j + 1)
    d = Hash.murmur(i + 1, j + 1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  # How bright a strike is, a seconds after it starts: a faint leader, the
  # return stroke, a dark gap, a restrike, then a fading afterglow.
  defp flash(a) when a < 0 or a > 1, do: 0
  defp flash(a) when a < 0.05, do: 0.3
  defp flash(a) when a < 0.15, do: 1
  defp flash(a) when a < 0.2, do: 0.15
  defp flash(a) when a < 0.3, do: 0.9
  defp flash(a), do: 0.9 * :math.exp(-(a - 0.3) / 0.18)

  defp hill(c),
    do: @rows - 3.6 - 1.2 * :math.sin(c * 0.07 + 0.8) - 0.5 * :math.sin(c * 0.19 + 2.1)

  defp side(c), do: min(1, min(c + 1, @cols - c) / 16)

  @impl true
  def init(_options) do
    rand = Int32.to_int32(7)

    # The cloud: a flat base with billows hanging from it, each a lobe with a
    # rounded underside, drifting along on the wind. It thins toward the
    # sides.
    {billows, rand} = billows(0, rand, [])

    # A bolt: one cell a row from the cloud to the ground, kicked a column or
    # two at a time in runs that switch side, always going down. Forks leave
    # it partway, run a few rows away from it, and give out in the air.
    bolts =
      for {{start, x0}, n} <- Enum.with_index(@strikes) do
        bolt(start, x0, Int32.to_int32(31 + n * 17), billows)
      end

    # Rain on the wind, a column left for every row it falls: far drops
    # short and slow, near ones longer streaks and faster.
    {drops, _} =
      Enum.map_reduce(1..@drops, rand, fn _, rand ->
        {near, rand} = Int32.mulberry32(rand)
        {x, rand} = Int32.mulberry32(rand)
        {y, rand} = Int32.mulberry32(rand)

        len =
          cond do
            near < 0.25 -> 1
            near < 0.7 -> 2
            true -> 3
          end

        {{x * (@cols + 20), y, 0.9 + near * 0.9, len}, rand}
      end)

    hills = List.to_tuple(for c <- 0..(@cols - 1), do: hill(c + 0.5))

    %{
      billows: billows,
      bolts: bolts,
      drops: drops,
      hills: hills,
      sides: List.to_tuple(for(c <- 0..(@cols - 1), do: side(c)))
    }
  end

  defp billows(x, rand, acc) when x >= @wrap - 4, do: {Enum.reverse(acc), rand}

  defp billows(x, rand, acc) do
    {w, rand} = Int32.mulberry32(rand)
    {d, rand} = Int32.mulberry32(rand)
    {step, rand} = Int32.mulberry32(rand)
    billows(x + (6 + step * 5), rand, [{x, 3.5 + w * 3.5, 1 + d * 2.6} | acc])
  end

  defp bottom(c, t, billows) do
    side = side(c)

    Enum.reduce(billows, @deck - 1.2 * (1 - side), fn {bx, w, d}, y ->
      x = JSMath.mod(JSMath.mod(c + 0.5 - bx + t * @drift, @wrap) + @wrap, @wrap) - 12

      if abs(x) < w do
        q = x / w
        max(y, @deck + d * side * :math.sqrt(1 - q * q))
      else
        y
      end
    end)
  end

  defp bolt(start, x0, rand, billows) do
    r0 = floor(bottom(x0, start, billows)) + 1
    ground = floor(hill(x0 + 0.5))
    {lean, rand} = Int32.mulberry32(rand)
    {x1, main, rand} = walk(x0, r0, ground, if(lean < 0.5, do: -1, else: 1), true, rand)
    main = List.to_tuple(main)
    {k, rand} = Int32.mulberry32(rand)

    {forks, _} =
      Enum.reduce(0..(1 + floor(k * 2)), {[], rand}, fn f, {forks, rand} ->
        {pick, rand} = Int32.mulberry32(rand)
        {c, r, ch} = elem(main, floor(tuple_size(main) * (0.2 + 0.5 * pick)))

        lean =
          cond do
            ch == "/" -> 1
            ch == "\\" -> -1
            rem(f, 2) == 1 -> 1
            true -> -1
          end

        {reach, rand} = Int32.mulberry32(rand)
        to = min(ground - 2, r + 3 + floor(reach * 4))
        {_, cells, rand} = walk(c + lean, r + 1, to, lean, false, rand)
        {forks ++ cells, rand}
      end)

    %{start: start, x0: x0, x1: x1, ground: ground, main: Tuple.to_list(main), forks: forks}
  end

  defp walk(c, from, to, lean, main, rand) do
    {c, _, _, cells, rand} =
      Enum.reduce(from..(to - 1)//1, {c, lean, 0, [], rand}, fn r, {c, dir, run, cells, rand} ->
        {dir, run, rand} =
          if run <= 0 do
            {dir, rand} = turn(dir, lean, main, rand)
            {r2, rand} = Int32.mulberry32(rand)
            {dir, 1 + floor(r2 * 3), rand}
          else
            {dir, run - 1, rand}
          end

        {r3, rand} = Int32.mulberry32(rand)

        {dx, rand} =
          if r3 < if(main, do: 0.22, else: 0.15) do
            {0, rand}
          else
            {r4, rand} = Int32.mulberry32(rand)
            {dir * if(r4 < 0.3, do: 2, else: 1), rand}
          end

        ch =
          cond do
            dx < 0 -> "/"
            dx > 0 -> "\\"
            true -> "|"
          end

        cells = if c >= 0 and c < @cols, do: [{c, r, ch} | cells], else: cells
        {c + dx, dir, run, cells, rand}
      end)

    {c, Enum.reverse(cells), rand}
  end

  defp turn(dir, _lean, true, rand) do
    {r, rand} = Int32.mulberry32(rand)
    dir = if r < 0.5, do: -dir, else: dir
    {if(dir == 0, do: 1, else: dir), rand}
  end

  defp turn(_dir, lean, false, rand), do: {lean, rand}

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)

    {lit, bolt, age} =
      for b <- state.bolts, a <- [u - b.start, u - b.start + @loop], reduce: {0, nil, 0} do
        {lit, bolt, age} ->
          f = flash(a)
          if f > lit, do: {f, b, a}, else: {lit, bolt, age}
      end

    out =
      %{}
      |> rain(state, t)
      |> cloud(state, t, lit, bolt)
      |> land(state, lit)
      |> strike(bolt, lit, age)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, c + r * @cols, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # Rain first, from the cloud to the hills.
  defp rain(out, state, t) do
    fall = @rows - 3

    for {x, y0, speed, len} <- state.drops,
        y = 3 + JSMath.mod(y0 + t * speed * 0.8, 1) * fall,
        i <- 0..(len - 1),
        r = floor(y) - i,
        c =
          floor(JSMath.mod(JSMath.mod(x - (y - 3) + i, @cols + 20) + @cols + 20, @cols + 20) - 10),
        c >= 0 and c < @cols and r >= 0 and r < elem(state.hills, c) - 0.6,
        reduce: out do
      out -> Map.put(out, c + r * @cols, if(len > 1, do: ",", else: "."))
    end
  end

  # The cloud, dim until a flash lights it all over, brightest over the bolt;
  # its underside drawn as an edge.
  defp cloud(out, state, t, lit, bolt) do
    drift = t * @drift * 0.2

    for c <- 0..(@cols - 1), reduce: out do
      out ->
        y = bottom(c, t, state.billows)
        side = elem(state.sides, c)

        near =
          if bolt do
            q = (c - bolt.x0) / 12
            :math.exp(-(q * q))
          else
            0
          end

        light = 0.5 + 0.35 * lit + 0.6 * lit * near

        Enum.reduce(0..floor(y)//1, out, fn r, out ->
          cloud_cell(out, c, r, y, side, light, drift)
        end)
    end
  end

  defp cloud_cell(out, c, r, y, _side, _light, _drift) when r + 1 > y,
    do: Map.put(out, c + r * @cols, elem(@edge, min(3, floor((y - r) * 4))))

  defp cloud_cell(out, c, r, y, side, light, drift) do
    # Thicker toward the underside, broken into rags toward the sides.
    n = noise(c * 0.2 + drift, r * 0.8 + 3)

    if n < 0.45 - 0.2 * r + 0.5 * (1 - side) do
      out
    else
      v =
        (0.3 + 0.3 * max(0, 1 - (y - r - 1) / 2.5) + 0.6 * (n - 0.5)) * light * (0.5 + 0.5 * side)

      Map.put(out, c + r * @cols, elem(@cloud, max(1, min(9, JSMath.round(v * 9)))))
    end
  end

  # The land: a dark outline of hills; a flash lights the slopes from the
  # skyline down, more of them the brighter it is.
  defp land(out, state, lit) do
    for c <- 0..(@cols - 1), reduce: out do
      out ->
        y = elem(state.hills, c)
        r = floor(y)
        out = Map.put(out, c + r * @cols, elem(@skyline, min(3, floor((1 - (y - r)) * 4))))

        Enum.reduce((r + 1)..(@rows - 1)//1, out, fn rr, out ->
          g = lit * (1.1 - (rr - y) / 4) - 0.2

          ch =
            cond do
              g > 0.55 -> "="
              g > 0.3 -> "-"
              g > 0.08 -> "."
              true -> " "
            end

          Map.put(out, c + rr * @cols, ch)
        end)
    end
  end

  # The leader only gets partway down; the strokes show it all, forks too
  # while it is brightest; the afterglow keeps just the channel. Where it
  # strikes, a splash of light on the ground.
  defp strike(out, bolt, lit, age) when bolt != nil and lit > 0.12 do
    n = length(bolt.main)
    reach = if age < 0.05, do: n * (age / 0.05) * 0.8, else: n

    out =
      bolt.main
      |> Enum.with_index()
      |> Enum.reduce(out, fn {{c, r, ch}, i}, out ->
        if i < reach, do: Map.put(out, c + r * @cols, if(lit > 0.4, do: ch, else: ":")), else: out
      end)

    out =
      if lit > 0.6,
        do:
          Enum.reduce(bolt.forks, out, fn {c, r, ch}, out -> Map.put(out, c + r * @cols, ch) end),
        else: out

    if lit > 0.4 and age >= 0.05 do
      for {dc, ch} <- @splash, bolt.x1 + dc >= 0 and bolt.x1 + dc < @cols, reduce: out do
        out -> Map.put(out, bolt.x1 + dc + bolt.ground * @cols, ch)
      end
    else
      out
    end
  end

  defp strike(out, _bolt, _lit, _age), do: out
end
