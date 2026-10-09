defmodule Ascii.Pieces.BigText do
  @moduledoc """
  A block-letter banner with a line shadow and a passing glint.

  A banner in a hand-made five-row block font with a drop shadow drawn in
  double lines, and a glint that sweeps across now and then: a heading, in
  your words and, letter by letter, your colours.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with the new text, the glint carrying on, being a function of play
  time.

    * `text` - the words, in capitals whatever their case. The font has
      `A` to `Z`, `0` to `9`, `.`, `,`, `!`, `?`, `'`, `:`, `-`, `+`, `=`,
      `/`, `_` and the space; any other character is left out. A pixel is
      two columns wide (square, as cells are twice as tall as wide) when
      the text fits, about six letters, and one column when it does not,
      about twelve; past that, it is cut at the frame's edge. Default
      `"hello"`.

  The frame is always 66 by 8, the banner centred in it.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `letter` - the letters' ink, glint and all; and `letter.<n>`, each
      letter by its place in the text from 1, counting every character,
      spaces too (so `w` is `letter.7` in "hello world"). Colours for the
      numbered letters set a heading in your own palette.
    * `shadow` - the double-line shadow, grey.

  ## Keys and clicks

  It takes none: it is a heading, and `Ascii.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still
  tells your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): which letter, say.

  ## Screen readers

  `Ascii.describe/1` reads the text, its spaces closed up: "big text:
  hello". A text of only spaces gives the piece's name and note.

  ## Example

  ```elixir
  colours = %{"letter.1" => "#3fb950", "letter.2" => "#58a6ff", "shadow" => "#8b949e"}
  banner = Ascii.new!("big-text", options: %{text: "ok!"}, parts: colours)
  {frame, _banner} = Ascii.frame(banner, 0.0)
  frame.palette
  #=> [nil, "#3fb950", "#58a6ff", "#8b949e"]

  Ascii.describe(banner)
  #=> "big text: ok!"
  ```

  ```heex
  <Ascii.Phoenix.live_player id="heading" piece="big-text" options={%{text: @title}} ink="#ff5f6d,#ffc371" />
  ```

  Ported from `src/pieces/big-text.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{JSMath, Parts}
  import Bitwise

  @meta %Ascii.Meta{
    name: "big text",
    category: :type,
    note: "a block-letter banner with a line shadow and a passing glint",
    cols: 66,
    rows: 8,
    fps: 24,
    options: %{text: "hello"},
    loop: 16,
    parts: [{"letter", nil}, {"shadow", "#8b949e"}]
  }

  # Five rows each, # is ink. Widths vary, so I is one pixel and M is five.
  @font %{
    "A" => ".##.|#..#|####|#..#|#..#",
    "B" => "###.|#..#|###.|#..#|###.",
    "C" => ".###|#...|#...|#...|.###",
    "D" => "###.|#..#|#..#|#..#|###.",
    "E" => "####|#...|###.|#...|####",
    "F" => "####|#...|###.|#...|#...",
    "G" => ".###|#...|#.##|#..#|.###",
    "H" => "#..#|#..#|####|#..#|#..#",
    "I" => "#|#|#|#|#",
    "J" => "...#|...#|...#|#..#|.##.",
    "K" => "#..#|#.#.|##..|#.#.|#..#",
    "L" => "#...|#...|#...|#...|####",
    "M" => "#...#|##.##|#.#.#|#...#|#...#",
    "N" => "#...#|##..#|#.#.#|#..##|#...#",
    "O" => ".##.|#..#|#..#|#..#|.##.",
    "P" => "###.|#..#|###.|#...|#...",
    "Q" => ".##.|#..#|#..#|#.#.|.#.#",
    "R" => "###.|#..#|###.|#.#.|#..#",
    "S" => ".###|#...|.##.|...#|###.",
    "T" => "#####|..#..|..#..|..#..|..#..",
    "U" => "#..#|#..#|#..#|#..#|.##.",
    "V" => "#...#|#...#|#...#|.#.#.|..#..",
    "W" => "#...#|#...#|#.#.#|##.##|#...#",
    "X" => "#...#|.#.#.|..#..|.#.#.|#...#",
    "Y" => "#...#|.#.#.|..#..|..#..|..#..",
    "Z" => "####|...#|..#.|.#..|####",
    "0" => "###|#.#|#.#|#.#|###",
    "1" => ".#.|##.|.#.|.#.|###",
    "2" => "###|..#|###|#..|###",
    "3" => "###|..#|.##|..#|###",
    "4" => "#.#|#.#|###|..#|..#",
    "5" => "###|#..|###|..#|###",
    "6" => "###|#..|###|#.#|###",
    "7" => "###|..#|..#|..#|..#",
    "8" => "###|#.#|###|#.#|###",
    "9" => "###|#.#|###|..#|###",
    "." => ".|.|.|.|#",
    "," => ".|.|.|#|#",
    "!" => "#|#|#|.|#",
    "?" => "###|..#|.##|...|.#.",
    "'" => "#|#|.|.|.",
    ":" => ".|#|.|#|.",
    "-" => "...|...|###|...|...",
    "+" => "...|.#.|###|.#.|...",
    "=" => "...|###|...|###|...",
    "/" => "..#|..#|.#.|#..|#..",
    "_" => "...|...|...|...|###",
    " " => ".."
  }

  # Shadow cells by which neighbours they join: up 1, down 2, left 4, right 8.
  @join {" ", "║", "║", "║", "═", "╝", "╗", "╣", "═", "╚", "╔", "╠", "═", "╩", "╦", "╬"}
  @u 1
  @d 2
  @l 4
  @r 8

  @sweep 2.4
  @period 3.2

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{text: text}) do
    %{cols: cols, rows: rows} = @meta
    {ink, x0, span} = layout(text)
    at = fn c, r -> if Map.has_key?(ink, {c, r}), do: 1, else: 0 end

    # The shadow is the letters' outline moved half a cell right and down, so
    # each empty cell draws the outline edges that meet at its top left corner.
    grid =
      for r <- 0..(rows - 1), c <- 0..(cols - 1) do
        if at.(c, r) == 1 do
          nil
        else
          a = at.(c - 1, r - 1)
          b = at.(c, r - 1)
          d = at.(c - 1, r)

          edges =
            if(a != b, do: @u, else: 0) ||| if(d == 1, do: @d, else: 0) |||
              if(a != d, do: @l, else: 0) ||| if(b == 1, do: @r, else: 0)

          # Where two letters touch only at that corner, the shadow turns down and right.
          elem(@join, if(edges == 15, do: @d ||| @r, else: edges))
        end
      end

    %{
      grid: grid |> Enum.chunk_every(cols) |> Enum.map(&Enum.with_index/1),
      left: x0 - 2,
      right: x0 + span + 9
    }
  end

  # The letters' ink: each cell's place in the text (counting from 1), with
  # where the banner starts and how wide it is. A character the font lacks
  # is left out; one that is two capitals (ß) is both.
  defp layout(text) do
    %{cols: cols, rows: rows} = @meta

    glyphs =
      for {char, n} <- text |> String.codepoints() |> Enum.with_index(1),
          ch <- char |> String.upcase() |> String.codepoints(),
          g = @font[ch],
          do: {n, String.split(g, "|")}

    # Each pixel is two columns by one row, so it is square; one column narrower if it would not fit.
    span = fn s ->
      Enum.reduce(glyphs, -1, fn {_n, g}, w -> w + String.length(hd(g)) * s + 2 end)
    end

    s = if span.(2) <= cols - 2, do: 2, else: 1
    x0 = max(0, Integer.floor_div(cols - span.(s), 2))
    y0 = div(rows - 6, 2)

    {ink, _} =
      Enum.reduce(glyphs, {%{}, x0}, fn {n, g}, {ink, x} ->
        ink =
          for {line, y} <- Enum.with_index(g),
              {"#", i} <- Enum.with_index(String.graphemes(line)),
              k <- 0..(s - 1),
              x + i * s + k < cols,
              reduce: ink,
              do: (acc -> Map.put(acc, {x + i * s + k, y0 + y}, n))

        {ink, x + String.length(hd(g)) * s + 2}
      end)

    {ink, x0, span.(s)}
  end

  @impl true
  def frame(%{grid: grid, left: left, right: right} = state, t, env) do
    # The glint crosses at an even pace, then rests out of sight. Frame 0 is at rest.
    u = JSMath.mod(JSMath.mod(t - 0.5, @period) + @period, @period) / @sweep
    p = if u < 1, do: left + (right - left) * u, else: -99

    lines =
      for {row, r} <- Enum.with_index(grid) do
        for {g, c} <- row do
          if g != nil do
            g
          else
            d = abs(c + 1.2 * r - p)

            # Ink is a dense shade on a dark page so the glint can be brighter, and solid on paper.
            cond do
              env.paper and d < 1.2 -> "▒"
              env.paper and d < 2.4 -> "▓"
              env.paper -> "█"
              d < 2.4 -> "█"
              true -> "▓"
            end
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # This port's own: the parts of a frame. The letters are where the
  # options lay them out, whatever shade the glint gives them; every other
  # mark is the shadow.

  @impl true
  def parts(%{lines: lines}, %{text: text}) do
    {ink, _x0, _span} = layout(text)

    for {line, r} <- Enum.with_index(lines) do
      Parts.cells(line, fn
        _cp, c when is_map_key(ink, {c, r}) -> "letter.#{Map.fetch!(ink, {c, r})}"
        ?\s, _c -> nil
        _cp, _c -> "shadow"
      end)
    end
  end

  @impl true
  def describe(%{text: text}) do
    case String.split(text) do
      [] -> nil
      words -> "big text: " <> Enum.join(words, " ")
    end
  end
end
