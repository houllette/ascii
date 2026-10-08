defmodule AsciiArt.Pieces.Dissolve do
  @moduledoc """
  Words that crumble to dust and condense into the next.

  A word in smooth stroked capitals crumbles letter by letter, its dust
  sinking out of each letter, while the next word's dust gathers onto its
  strokes.

  Ported from `src/pieces/dissolve.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Hash, Text}

  @meta %AsciiArt.Meta{
    name: "dissolve",
    category: :type,
    note: "words that crumble to dust and condense into the next",
    cols: 64,
    rows: 13,
    fps: 20,
    options: %{words: ["hello", "hola", "ciao", "salut"]},
    loop: 16.8
  }

  # Capitals as polylines in a 4 by 6 box, y down.
  @strokes %{
    "A" => [[0, 6, 1.6, 0, 2.4, 0, 4, 6], [0.7, 4, 3.3, 4]],
    "B" => [[0, 0, 0, 6, 3, 6, 4, 5, 4, 4, 3, 3, 0, 3], [0, 0, 2.5, 0, 3.5, 1, 3.5, 2, 2.5, 3]],
    "C" => [[4, 1, 3, 0, 1, 0, 0, 1, 0, 5, 1, 6, 3, 6, 4, 5]],
    "D" => [[0, 0, 0, 6, 2.5, 6, 4, 4.5, 4, 1.5, 2.5, 0, 0, 0]],
    "E" => [[4, 0, 0, 0, 0, 6, 4, 6], [0, 3, 3, 3]],
    "F" => [[4, 0, 0, 0, 0, 6], [0, 3, 3, 3]],
    "G" => [[4, 1, 3, 0, 1, 0, 0, 1, 0, 5, 1, 6, 3, 6, 4, 5, 4, 3, 2, 3]],
    "H" => [[0, 0, 0, 6], [4, 0, 4, 6], [0, 3, 4, 3]],
    "I" => [[1, 0, 3, 0], [2, 0, 2, 6], [1, 6, 3, 6]],
    "J" => [[1.5, 0, 4, 0], [3, 0, 3, 5, 2, 6, 1, 6, 0, 5]],
    "K" => [[0, 0, 0, 6], [4, 0, 0, 3.6], [1.5, 2.25, 4, 6]],
    "L" => [[0, 0, 0, 6, 4, 6]],
    "M" => [[0, 6, 0, 0, 2, 3.5, 4, 0, 4, 6]],
    "N" => [[0, 6, 0, 0, 4, 6, 4, 0]],
    "O" => [[1, 0, 3, 0, 4, 1, 4, 5, 3, 6, 1, 6, 0, 5, 0, 1, 1, 0]],
    "P" => [[0, 6, 0, 0, 3, 0, 4, 1, 4, 2, 3, 3, 0, 3]],
    "Q" => [[1, 0, 3, 0, 4, 1, 4, 5, 3, 6, 1, 6, 0, 5, 0, 1, 1, 0], [2.4, 4.4, 4, 6.2]],
    "R" => [[0, 6, 0, 0, 3, 0, 4, 1, 4, 2, 3, 3, 0, 3], [2.2, 3, 4, 6]],
    "S" => [[4, 1, 3, 0, 1, 0, 0, 1, 0, 2, 1, 3, 3, 3, 4, 4, 4, 5, 3, 6, 1, 6, 0, 5]],
    "T" => [[0, 0, 4, 0], [2, 0, 2, 6]],
    "U" => [[0, 0, 0, 5, 1, 6, 3, 6, 4, 5, 4, 0]],
    "V" => [[0, 0, 2, 6, 4, 0]],
    "W" => [[0, 0, 1, 6, 2, 2, 3, 6, 4, 0]],
    "X" => [[0, 0, 4, 6], [4, 0, 0, 6]],
    "Y" => [[0, 0, 2, 3], [4, 0, 2, 3, 2, 6]],
    "Z" => [[0, 0, 4, 0, 0, 6, 4, 6]],
    "0" => [[1, 0, 2, 0, 3, 1, 3, 5, 2, 6, 1, 6, 0, 5, 0, 1, 1, 0]],
    "1" => [[0.5, 1, 1.5, 0, 1.5, 6], [0.5, 6, 2.5, 6]],
    "2" => [[0, 1, 1, 0, 3, 0, 4, 1, 4, 2, 0, 6, 4, 6]],
    "3" => [[0, 1, 1, 0, 3, 0, 4, 1, 4, 2, 3, 3, 1.5, 3], [3, 3, 4, 4, 4, 5, 3, 6, 1, 6, 0, 5]],
    "4" => [[3, 6, 3, 0, 0, 4, 4, 4]],
    "5" => [[4, 0, 0, 0, 0, 3, 3, 3, 4, 4, 4, 5, 3, 6, 0, 6]],
    "6" => [[3.5, 0, 1.5, 0, 0, 1.5, 0, 5, 1, 6, 3, 6, 4, 5, 4, 4, 3, 3, 1, 3, 0, 4]],
    "7" => [[0, 0, 4, 0, 1.5, 6]],
    "8" => [
      [
        1,
        3,
        0,
        2,
        0,
        1,
        1,
        0,
        3,
        0,
        4,
        1,
        4,
        2,
        3,
        3,
        1,
        3,
        0,
        4,
        0,
        5,
        1,
        6,
        3,
        6,
        4,
        5,
        4,
        4,
        3,
        3
      ]
    ],
    "9" => [[0.5, 6, 2.5, 6, 4, 4.5, 4, 1, 3, 0, 1, 0, 0, 1, 0, 2, 1, 3, 4, 3]],
    "." => [[2, 6, 2, 6]],
    "," => [[2, 5.6, 1.5, 7]],
    "!" => [[2, 0, 2, 4], [2, 6, 2, 6]],
    "?" => [[0, 1, 1, 0, 3, 0, 4, 1, 4, 2, 2, 3.5, 2, 4.2], [2, 6, 2, 6]],
    "'" => [[2, 0, 2, 1.5]],
    "-" => [[1, 3, 3, 3]]
  }
  @ramp {" ", ".", "·", "░", "▒", "▓", "█"}
  # Seconds each word rests, and the change to the next.
  @hold 1.6
  @trans 2.6
  # Letter by letter, and cell by cell within one.
  @stagger 0.2
  @jitter 0.22
  # A cell wearing away, a cell filling in, the new word's lag.
  @erode 0.3
  @fade 0.5
  @later 1
  # Stroke radius, a little more on slanted strokes so they hold their weight.
  @r 0.5
  @rd 0.6
  # Columns from one letter's last stroke to the next one's first.
  @gap 4

  @compile {:inline, hash: 2, ease: 1}

  @impl true
  def meta, do: @meta

  defp hash(a, b), do: Hash.scene(a, b)

  defp ease(x) when x <= 0, do: 0
  defp ease(x) when x >= 1, do: 1
  defp ease(x), do: x * x * (3 - 2 * x)

  defp glyph(ch) do
    case @strokes do
      %{^ch => g} -> g
      _ when ch == " " -> []
      _ -> @strokes["?"]
    end
  end

  defp span(g) do
    case g |> Enum.flat_map(&Enum.take_every(&1, 2)) do
      [] -> {0, 2}
      xs -> Enum.min_max(xs)
    end
  end

  # One unit is a row tall and two columns wide, smaller if the longest word needs it.
  defp wide(w, u) do
    gap = max(2, JSMath.round(@gap * u))

    Enum.reduce(w, 0, fn ch, a ->
      {lo, hi} = span(glyph(ch))
      a + JSMath.round(2 * u * (hi - lo)) + gap
    end) - gap + 4 * u * @r
  end

  @impl true
  def init(%{words: words}) do
    %{rows: rows} = @meta
    given = if is_binary(words), do: Regex.split(~r/[,\s]+/u, words), else: words
    given = Enum.reject(given, &(&1 == ""))

    list =
      Enum.map(
        if(given == [], do: ["hello"], else: given),
        &(&1 |> String.upcase() |> Text.chars())
      )

    unit = shrink(min(1, (rows - 2) / (6 + 2 * @r)), list)
    gap = max(2, JSMath.round(@gap * unit))
    baked = list |> Enum.map(&bake(&1, unit, gap)) |> List.to_tuple()
    %{baked: baked, period: length(list) * (@hold + @trans)}
  end

  defp shrink(unit, list) do
    if unit > 0.3 and Enum.max(Enum.map(list, &wide(&1, unit))) > @meta.cols - 4,
      do: shrink(unit - 0.02, list),
      else: unit
  end

  # Bake each word's ink coverage and which letter every column belongs to. The
  # pen advances in whole columns, so every gap between letters is the same.
  defp bake(w, unit, gap) do
    %{cols: cols, rows: rows} = @meta
    y0 = rows / 2 - 3 * unit
    pen = JSMath.round((cols - wide(w, unit)) / 2 + 2 * unit * @r)

    {cover, centres, _} =
      Enum.reduce(w, {%{}, [], pen}, fn ch, {cover, centres, pen} ->
        g = glyph(ch)
        {lo, hi} = span(g)
        width = JSMath.round(2 * unit * (hi - lo))
        segs = segments(g)

        cover =
          for r <- 0..(rows - 1),
              c <- max(0, pen - 3)..(min(cols, pen + width + 3) - 1)//1,
              reduce: cover do
            cover ->
              hit = hits(segs, lo, c, r, pen, unit, y0)
              k = r * cols + c
              Map.put(cover, k, JSMath.fround(max(Map.get(cover, k, 0.0), hit / 9)))
          end

        {cover, [pen + width / 2 | centres], pen + width + gap}
      end)

    centres = centres |> Enum.reverse() |> Enum.with_index()
    first = centres |> hd() |> elem(0)

    slot =
      for c <- 0..(cols - 1) do
        {_, best} =
          Enum.reduce(centres, {first, 0}, fn {x, i}, {bx, best} ->
            if abs(x - c) < abs(bx - c), do: {x, i}, else: {bx, best}
          end)

        JSMath.i8(best)
      end

    %{
      cover: List.to_tuple(for(k <- 0..(cols * rows - 1), do: Map.get(cover, k, 0.0))),
      slot: List.to_tuple(slot)
    }
  end

  # Each segment of a glyph as its start, its run, its squared length and its radius.
  defp segments(g) do
    for p <- g, [ax, ay, bx, by] <- Enum.chunk_every(p, 4, 2, :discard) do
      dx = bx - ax
      dy = by - ay
      {ax, ay, dx, dy, dx * dx + dy * dy, if(dx != 0 and dy != 0, do: @rd, else: @r)}
    end
  end

  # How many of a cell's nine samples fall inside a stroke.
  defp hits(segs, lo, c, r, pen, unit, y0) do
    for j <- 0..2, i <- 0..2, reduce: 0 do
      hit ->
        gx = lo + (c + (i + 0.5) / 3 - pen) / (2 * unit)
        gy = (r + (j + 0.5) / 3 - y0) / unit
        if Enum.any?(segs, &inside?(&1, gx, gy)), do: hit + 1, else: hit
    end
  end

  # Whether the distance from (x, y) to the segment, less the stroke's radius,
  # is at most zero. Math.hypot is never below its largest argument, so a
  # point farther than the radius along either axis is outside without it.
  defp inside?({ax, ay, dx, dy, l, rad}, x, y) do
    k = if l != 0, do: max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / l)), else: 0
    px = x - ax - k * dx
    py = y - ay - k * dy
    abs(px) <= rad and abs(py) <= rad and JSMath.hypot(px, py) - rad <= 0
  end

  @impl true
  def frame(%{baked: baked, period: period} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    count = tuple_size(baked)
    u = JSMath.mod(JSMath.mod(t + 1, period) + period, period)
    n = JSMath.floor(u / (@hold + @trans))
    tau = u - n * (@hold + @trans) - @hold
    a = elem(baked, rem(n, count))
    b = elem(baked, rem(n + 1, count))

    {vals, dust} =
      if tau > 0 do
        Enum.map_reduce(0..(cols * rows - 1), %{}, fn k, dust ->
          cell(k, rem(k, cols), div(k, cols), n, tau, a, b, dust)
        end)
      else
        {Tuple.to_list(a.cover), %{}}
      end

    lines =
      vals
      |> Enum.with_index()
      |> Enum.map(fn {v, k} -> elem(@ramp, JSMath.round(max(v, Map.get(dust, k, 0.0)) * 6)) end)
      |> Enum.chunk_every(cols)
      |> Enum.intersperse(?\n)

    {lines, nil, state}
  end

  defp cell(k, c, r, n, tau, a, b, dust) do
    av = elem(a.cover, k)
    bv = elem(b.cover, k)
    {v, dust} = if av > 0, do: old(k, c, r, n, tau, av, elem(a.slot, c), dust), else: {0, dust}
    {v, dust} = if bv > 0, do: new(k, c, r, n, tau, bv, elem(b.slot, c), v, dust), else: {v, dust}
    {JSMath.fround(v), dust}
  end

  # The old cell wears thin, then about half of them let go as a grain that
  # falls out of the letter, drifting a little right, and fades.
  defp old(k, c, r, n, tau, a, slot, dust) do
    go = slot * @stagger + hash(k, n) * @jitter
    e = (tau - go) / @erode

    cond do
      a <= 0.3 or hash(k, n + 7) > 0.5 ->
        {a * (1 - ease(e)), dust}

      e < 1 ->
        {a * (1 - 0.5 * max(0, e)), dust}

      true ->
        age = tau - go - @erode
        life = 0.5 + 0.35 * hash(k, n + 57)

        if age < life do
          vx = 0.6 + 1.4 * hash(k, n + 31)
          vy = 0.3 + 0.6 * hash(k, n + 83)

          {0,
           splat(
             dust,
             c + 0.5 + vx * age,
             r + vy * age + 4 * age * age,
             0.5 * (1 - 0.7 * age / life)
           )}
        else
          {0, dust}
        end
    end
  end

  # The new cell's grain, for about half of them, gathers in toward its
  # stroke from a cell or two away, and the cell fills in around it.
  defp new(k, c, r, n, tau, b, slot, v, dust) do
    land = @later + slot * @stagger + hash(k, n + 977) * @jitter

    cond do
      tau >= land ->
        e = ease((tau - land) / @fade)
        {max(v, b * if(b > 0.3, do: 0.4 + 0.6 * e, else: e)), dust}

      b > 0.3 and hash(k, n + 9) < 0.55 ->
        life = 0.45 + 0.3 * hash(k, n + 211)
        f = (land - tau) / life

        if f < 1 do
          q = f * f
          th = 6.283 * hash(k, n + 401)
          d = 0.8 + 1.2 * hash(k, n + 613)
          x = c + 1.8 * d * :math.cos(th) * q
          y = r + d * :math.sin(th) * q
          {v, splat(dust, x, y, 0.17 + 0.3 * (1 - f))}
        else
          {v, dust}
        end

      true ->
        {v, dust}
    end
  end

  defp splat(dust, x, y, d) do
    %{cols: cols, rows: rows} = @meta
    c = JSMath.round(x)
    r = JSMath.round(y)

    if c >= 0 and c < cols and r >= 0 and r < rows do
      i = r * cols + c
      Map.put(dust, i, JSMath.fround(max(Map.get(dust, i, 0.0), d)))
    else
      dust
    end
  end
end
