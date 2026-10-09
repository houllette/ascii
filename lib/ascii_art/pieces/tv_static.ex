defmodule AsciiArt.Pieces.TvStatic do
  @moduledoc """
  Snow on an old set that tunes into a test card and loses it.

  An old set showing snow, with a hum bar rolling through it. The dial clicks
  over, a test card rolls into place and holds, then is lost.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `set` - the old set around the screen, its cabinet, dial and knobs.
      Default `true`; `false` fills the whole frame with the screen.

  The picture is always 58 by 26.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `AsciiArt.Ink`),
  or on a page a CSS variable. On a light page, give it `paper: true`: its
  shading reads from the other end of its ramp, so dense characters still mean
  dark. It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "tv static: snow on an old
  set that tunes into a test card and loses it". A player's or a component's
  `label` gives words of your own, as "static on an old television".

  ## Example

  ```elixir
  {frame, _} = "tv-static" |> AsciiArt.new!(options: %{set: false}) |> AsciiArt.frame(1.0)
  {frame.cols, frame.rows}
  #=> {58, 26}
  ```

  ```heex
  <AsciiArt.Phoenix.player socket={@socket} id="snow" piece="tv-static" options={%{set: false}} />
  ```

  Ported from `src/pieces/tv-static.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Hash

  @meta %AsciiArt.Meta{
    name: "tv static",
    category: :effects,
    note: "snow on an old set that tunes into a test card and loses it",
    cols: 58,
    rows: 26,
    fps: 20,
    options: %{set: true}
  }

  @cols 58
  @rows 26
  @ramp {" ", ".", ":", "+", "░", "▒", "▓", "█"}
  @n 7
  # Seconds: snow, tuning in, the card, losing it, snow.
  @loop 10
  # Ramp levels, brightest bar first, and the reversed strip under the bars.
  @bars {7, 6, 5, 4, 3, 2, 1}
  @castle {1, 0, 3, 0, 5, 0, 7}
  @bottom [{0.17, 5}, {0.34, 7}, {0.51, 3}, {0.68, 0}, {0.73, 1}, {0.78, 0}, {0.83, 2}, {1, 0}]
  # Where the snow steps up a level.
  @snow [0.36, 0.48, 0.6, 0.7, 0.8, 0.9, 0.98]
  @dial {"╱", "─", "╲", "│"}

  @compile {:inline, ink: 2, snow_level: 1}

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{set: set}) do
    # The picture area, and which of its cells the curved tube leaves out.
    {x0, y0, sw, sh} = if set, do: {4, 7, 39, 15}, else: {0, 0, @cols, @rows}
    frame = if set, do: draw_set(), else: blank()
    card = draw_card(sw, sh)

    picture =
      for r <- 0..(sh - 1) do
        List.to_tuple(for c <- 0..(sw - 1), do: inside?(set, c, r, sw, sh))
      end

    rows =
      for r <- 0..(@rows - 1) do
        line = for c <- 0..(@cols - 1), do: Map.get(frame, {r, c}, " ")

        if r >= y0 and r < y0 + sh,
          do: {Enum.take(line, x0), Enum.drop(line, x0 + sw)},
          else: line
      end

    %{
      set: set,
      sw: sw,
      sh: sh,
      card: card,
      picture: picture,
      rows: rows,
      y0: y0
    }
  end

  defp blank, do: %{}

  defp inside?(false, _c, _r, _sw, _sh), do: true

  defp inside?(true, c, r, sw, sh) do
    x = (c + 0.5 - sw / 2) / (sw / 2)
    y = (r + 0.5 - sh / 2) / (sh / 2)
    :math.pow(x, 6) + :math.pow(y, 6) <= 1.02
  end

  defp smooth(a, b, v) do
    x = max(0.0, min(1.0, (v - a) / (b - a)))
    x * x * (3 - 2 * x)
  end

  # The set: cabinet, rounded screen bezel, two knobs, a grille, legs and ears.
  defp draw_set do
    g =
      %{}
      |> box(1, 5, 56, 23, "╭╮╰╯─│")
      |> box(3, 6, 43, 22, "╭╮╰╯─│")
      # The channel knob, the volume knob and the speaker.
      |> box(46, 8, 52, 10, "╭╮╰╯─│")
      |> box(46, 12, 52, 14, "╭╮╰╯─│")
      |> box(45, 16, 53, 21, "┌┐└┘─│")

    g = for y <- 17..20, x <- 46..52, into: g, do: {{y, x}, "═"}
    g = g |> Map.put({13, 49}, "╲") |> put(25, 4, "▄▄███▄▄")

    g =
      Enum.reduce(1..4, g, fn k, g ->
        g |> Map.put({4 - k, 25 - k}, "╲") |> Map.put({4 - k, 31 + k}, "╱")
      end)

    g
    |> Map.put({0, 21}, "o")
    |> Map.put({0, 35}, "o")
    |> put(5, 24, "╱")
    |> put(4, 25, "╱")
    |> put(52, 24, "╲")
    |> put(53, 25, "╲")
  end

  defp put(g, x, y, s) do
    s
    |> String.codepoints()
    |> Enum.with_index(x)
    |> Enum.reduce(g, fn {ch, cx}, g -> Map.put(g, {y, cx}, ch) end)
  end

  defp box(g, x0, y0, x1, y1, chars) do
    [tl, tr, bl, br, h, v] = String.codepoints(chars)
    g = for x <- (x0 + 1)..(x1 - 1)//1, y <- [y0, y1], into: g, do: {{y, x}, h}
    g = for y <- (y0 + 1)..(y1 - 1)//1, x <- [x0, x1], into: g, do: {{y, x}, v}
    Map.merge(g, %{{y0, x0} => tl, {y0, x1} => tr, {y1, x0} => bl, {y1, x1} => br})
  end

  # The test card: bars over a reversed strip and a bottom strip of hard-edged
  # blocks, with a circle and a crosshair drawn across the middle. Cells hold
  # a ramp level or a character.
  defp draw_card(sw, sh) do
    card =
      for r <- 0..(sh - 1), c <- 0..(sw - 1), into: %{} do
        u = (c + 0.5) / sw
        v = (r + 0.5) / sh
        bar = min(6, floor(u * 7))

        level =
          cond do
            v < 0.67 -> elem(@bars, bar)
            v < 0.75 -> elem(@castle, bar)
            true -> @bottom |> Enum.find(fn {stop, _} -> u < stop end) |> elem(1)
          end

        {{r, c}, level}
      end

    # The circle, row by row: its span in each row, outlined in box drawing.
    big_r = min(sh * 0.43, sw * 0.22) * 2
    cx = sw / 2
    cy = sh / 2

    span =
      for r <- 0..(sh - 1), into: %{} do
        y = (r + 0.5 - cy) * 2
        w = big_r * big_r - y * y

        if w < 0,
          do: {r, nil},
          else: {r, {ceil(cx - :math.sqrt(w) - 0.5), floor(cx + :math.sqrt(w) - 0.5)}}
      end

    mid = floor(sh / 2)
    mc = floor(sw / 2)

    card =
      Enum.reduce(0..(sh - 1), card, fn r, card ->
        case span[r] do
          nil ->
            card

          ab ->
            ring_row(card, r, ab, if(r < mid, do: span[r - 1], else: span[r + 1]), r < mid, mc)
        end
      end)

    # The crosshair, meeting the circle in tees.
    {a, b} = span[mid]
    card = for c <- (a + 1)..(b - 1)//1, into: card, do: {{mid, c}, "─"}
    card = for r <- 0..(sh - 1), span[r] != nil, into: card, do: {{r, mc}, "│"}
    first = Enum.find(0..(sh - 1), &(span[&1] != nil))
    last = Enum.find((sh - 1)..0//-1, &(span[&1] != nil))

    card =
      card
      |> Map.put({mid, a}, "├")
      |> Map.put({mid, b}, "┤")
      |> Map.put({mid, mc}, "┼")
      |> Map.put({first, mc}, "┬")
      |> Map.put({last, mc}, "┴")

    List.to_tuple(
      for r <- 0..(sh - 1), do: List.to_tuple(for(c <- 0..(sw - 1), do: card[{r, c}]))
    )
  end

  # The run out to the row nearer the middle's edge, stepped with corners.
  defp ring_row(card, r, {a, b}, near, up, mc) do
    {na, nb} = near || {mc + 1, mc - 1}

    card =
      for c <- a..b//1,
          (c > a and c < na and c < nb) or (c < b and c > nb and c > na),
          into: card,
          do: {{r, c}, "─"}

    card =
      if a < na do
        card
        |> Map.put({r, a}, if(up, do: "╭", else: "╰"))
        |> Map.put({r, na}, if(up, do: "╯", else: "╮"))
        |> Map.put({r, b}, if(up, do: "╮", else: "╯"))
        |> Map.put({r, nb}, if(up, do: "╰", else: "╭"))
      else
        card |> Map.put({r, a}, "│") |> Map.put({r, b}, "│")
      end

    if near, do: card, else: for(c <- (a + 1)..(b - 1)//1, into: card, do: {{r, c}, "─"})
  end

  defp ink(level, false), do: elem(@ramp, level)
  defp ink(level, true), do: elem(@ramp, @n - level)

  defp snow_level(v), do: Enum.count(Enum.take_while(@snow, &(v > &1)))

  @impl true
  def frame(state, t, env) do
    %{set: set, sw: sw, sh: sh, card: card, picture: picture, rows: rows, y0: y0} = state
    paper = env.paper
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)
    # The snow is new every frame.
    k = floor(t * @meta.fps)
    # How firmly the set holds the signal. Just before it locks, and just
    # before it is lost, the dial clicks through three stops.
    lock = smooth(1.6, 3.4, u) * (1 - smooth(6.6, 7.8, u))
    dial = max(0, min(min(3, floor((u - 1.1) * 8)), 3 - floor((u - 6.4) * 8)))
    snow = 1 - 0.97 * lock
    # Unlocked, the picture rolls (with its blanking bar) and its lines tear.
    roll = (1 - lock) * (1 - lock) * (sh + 2) * 2.5
    tear = (1 - lock) * 9
    # The hum bar's middle row, once a loop.
    hum = JSMath.mod(u / @loop + 0.45, 1) * (sh + 6) - 3
    # What a scan needs from the frame.
    f = %{k: k, paper: paper, lock6: :math.pow(lock, 6), snow: snow, sw: sw, card: card}

    pictures =
      picture
      |> Enum.with_index()
      |> Enum.map(fn {inside, r} ->
        dim = 1 - 0.45 * :math.exp(-square((r - hum) / 2.2))
        # Each scan line a little brighter or darker.
        line = 0.9 + 0.2 * Hash.murmur(k, r, 9)

        shift =
          JSMath.round(tear * :math.sin(r * 0.8 + u * 9) * Hash.murmur(Int32.sar(k, 2), r, 3))

        # The card row shown here.
        pr = floor(JSMath.mod(r + roll, sh + 2))
        row = %{r: r, dim: dim, line: line, shift: shift, pr: pr}
        scan(f, row, inside, 0, Hash.murmur(k, r, 1), [])
      end)
      |> List.to_tuple()

    lines =
      rows
      |> Enum.with_index()
      |> Enum.map(fn
        {{left, right}, r} -> [left, elem(pictures, r - y0), dial_at(right, r, set, dial)]
        {line, r} -> dial_at(line, r, set, dial)
      end)

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp square(x), do: x * x

  # The channel knob's pointer, at column 49 of row 9.
  defp dial_at(line, 9, true, dial),
    do: List.replace_at(line, 49 - (@cols - length(line)), elem(@dial, dial))

  defp dial_at(line, _r, _set, _dial), do: line

  defp scan(%{sw: sw}, _row, _inside, c, _prev, acc) when c == sw, do: Enum.reverse(acc)

  defp scan(f, row, inside, c, prev, acc) do
    if elem(inside, c) do
      {ch, prev} = pixel(f, row, c, prev)
      scan(f, row, inside, c + 1, prev, [ch | acc])
    else
      scan(f, row, inside, c + 1, prev, [" " | acc])
    end
  end

  # Snow is fine grain streaked along the line, as it is on a real tube,
  # mostly dots with now and then a brighter fleck.
  defp pixel(f, %{r: r} = row, c, prev) do
    %{k: k, paper: paper} = f
    n = Hash.murmur(k, r * 97 + c, 2)
    prev = 0.6 * n + 0.4 * prev
    noisy = Hash.murmur(k, r * 97 + c, 5) < f.snow

    ch =
      if noisy and Hash.murmur(k, r * 97 + c, 6) >= f.lock6 do
        ink(snow_level(prev * row.line * row.dim), paper)
      else
        pc = Integer.mod(c + row.shift, f.sw)
        x = if row.pr < tuple_size(f.card), do: f.card |> elem(row.pr) |> elem(pc), else: 0
        card_cell(x, noisy, n, paper)
      end

    {ch, prev}
  end

  # Once locked, what noise is left only nudges the card a shade.
  defp card_cell(x, true, n, paper) when is_integer(x),
    do: ink(max(0, min(@n, x + if(n < 0.5, do: -1, else: 1))), paper)

  defp card_cell(x, _noisy, _n, paper) when is_integer(x), do: ink(x, paper)
  defp card_cell(x, _noisy, _n, _paper), do: x
end
