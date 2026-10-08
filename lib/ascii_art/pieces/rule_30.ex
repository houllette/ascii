defmodule AsciiArt.Pieces.Rule30 do
  @moduledoc """
  One cell grows a row at a time under rules 30, 90 and 110.

  An elementary cellular automaton grown from one live cell, each generation
  a row, scrolling up. It runs rule 30, then 90, then 110, each from a fresh
  seed. Two generations to a character, so cells are square.

  Ported from `src/pieces/rule-30.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  import Bitwise

  @meta %AsciiArt.Meta{
    name: "rule 30",
    category: :generative,
    note: "one cell grows a row at a time under rules 30, 90 and 110",
    cols: 64,
    rows: 20,
    fps: 8,
    loop: 8.75
  }

  # Each rule, the column of its seed, and how many generations it runs:
  # short enough that its triangle never reaches the sides. Rule 90 stops on
  # the row that closes its fifth level of triangles; rule 110 grows only to
  # the left, so its seed sits right of centre.
  @rules [{30, 31, 32}, {90, 31, 32}, {110, 51, 40}]
  # Blank generations between one rule and the next.
  @gap 12
  # Character rows a second, one a frame.
  @speed 8
  # Cells past each side, so the edges never show.
  @extra 48

  @glyph {" ", "▀", "▄", "█"}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols} = @meta
    w = cols + 2 * @extra
    blank = List.duplicate(0, cols)

    # Every generation of the loop, cropped to the frame.
    tape =
      Enum.flat_map(@rules, fn {rule, at, gens} ->
        seed = List.duplicate(0, w) |> List.replace_at(@extra + at, 1)

        seed
        |> Stream.iterate(&generation(&1, rule))
        |> Enum.take(gens)
        |> Enum.map(&(&1 |> Enum.drop(@extra) |> Enum.take(cols)))
        |> Kernel.++(List.duplicate(blank, @gap))
      end)

    # Every run and gap is an even number of generations, so the tape scrolls
    # a whole character row at a time and each glyph keeps the same two
    # generations from frame to frame.
    tape
    |> Enum.chunk_every(2)
    |> Enum.map(fn [a, b] ->
      a |> Enum.zip_with(b, fn x, y -> elem(@glyph, x + 2 * y) end) |> IO.iodata_to_binary()
    end)
    |> List.to_tuple()
  end

  # The cells at either end are never written, so they stay dead.
  defp generation(cur, rule) do
    inner =
      cur
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.map(fn [l, c, r] -> band(bsr(rule, bor(bor(bsl(l, 2), bsl(c, 1)), r)), 1) end)

    [0 | inner] ++ [0]
  end

  # The newest generation is always the bottom row. At t = 0 the first
  # triangle sits two rows down from the top.
  @impl true
  def frame(lines, t, _env) do
    loop = tuple_size(lines)
    top = floor(t * @speed) - 2

    picture =
      for r <- 0..(@meta.rows - 1), do: elem(lines, Integer.mod(top + r, loop))

    {Enum.intersperse(picture, ?\n), nil, lines}
  end
end
