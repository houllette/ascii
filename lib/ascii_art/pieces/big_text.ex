defmodule AsciiArt.Pieces.BigText do
  @moduledoc """
  A block-letter banner with a line shadow and a passing glint.

  A banner in a hand-made five-row block font with a drop shadow drawn in
  double lines, and a glint that sweeps across now and then.

  Ported from `src/pieces/big-text.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "big text",
    category: :type,
    note: "a block-letter banner with a line shadow and a passing glint",
    cols: 66,
    rows: 8,
    fps: 24,
    options: %{text: "hello"},
    loop: 16
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

    glyphs =
      for ch <- text |> String.upcase() |> String.codepoints(),
          g = @font[ch],
          do: String.split(g, "|")

    # Each pixel is two columns by one row, so it is square; one column narrower if it would not fit.
    span = fn s -> Enum.reduce(glyphs, -1, fn g, w -> w + String.length(hd(g)) * s + 2 end) end
    s = if span.(2) <= cols - 2, do: 2, else: 1
    x0 = max(0, Integer.floor_div(cols - span.(s), 2))
    y0 = div(rows - 6, 2)

    {ink, _} =
      Enum.reduce(glyphs, {MapSet.new(), x0}, fn g, {ink, x} ->
        ink =
          for {line, y} <- Enum.with_index(g),
              {"#", i} <- Enum.with_index(String.graphemes(line)),
              k <- 0..(s - 1),
              x + i * s + k < cols,
              reduce: ink,
              do: (acc -> MapSet.put(acc, {x + i * s + k, y0 + y}))

        {ink, x + String.length(hd(g)) * s + 2}
      end)

    at = fn c, r -> if MapSet.member?(ink, {c, r}), do: 1, else: 0 end

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
      right: x0 + span.(s) + 9
    }
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
end
