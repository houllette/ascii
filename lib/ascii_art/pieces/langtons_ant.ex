defmodule AsciiArt.Pieces.LangtonsAnt do
  @moduledoc """
  Order, then chaos, then the ant builds its highway.

  An ant that turns right on a blank square and left on an inked one,
  flipping each square it leaves. Two squares to a character.

  Ported from `src/pieces/langtons-ant.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "langton's ant",
    category: :generative,
    note: "order, then chaos, then the ant builds its highway",
    cols: 72,
    rows: 25,
    fps: 30
  }

  # The board, in squares; the frame shows part of it.
  @n 200
  # The board square at the frame's top left, from the start.
  @x0 31
  @y0 -24
  # Play time against steps taken. The cycle opens as the highway sets off, so
  # the first frame already shows all three phases; then the ant walks out of
  # the frame, the board fades and it starts again from a blank board. The
  # highway starts at step 9977.
  @keys {{0, 10_350}, {2.0, 11_330}, {3.2, 11_330}, {3.2, 0}, {4.3, 100}, {5.6, 520},
         {12.4, 9977}, {13.2, 10_350}}
  @period 13.2
  @fade_from 2.4
  @fade_to 3.2

  # The frame is mirrored so the highway runs off to the lower right.
  @glyph {" ", "▀", "▄", "█"}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta

    # Each square fades at its own moment.
    {fade_at, _} =
      Enum.map_reduce(1..(cols * rows * 2), Int32.to_int32(7), fn _, rand ->
        {v, rand} = Int32.mulberry32(rand)
        {JSMath.fround(v), rand}
      end)

    fade_at = List.to_tuple(fade_at)

    # Per cell: the board squares it shows, top and bottom, and when each fades.
    cells =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          k = (r * cols + c) * 2
          {square(c, 2 * r), square(c, 2 * r + 1), elem(fade_at, k), elem(fade_at, k + 1)}
        end
      end

    Map.put(reset(), :cells, cells)
  end

  defp square(c, r), do: (div(@n, 2) + @y0 + r) * @n + div(@n, 2) + @x0 - c

  defp reset, do: %{board: MapSet.new(), x: div(@n, 2), y: div(@n, 2), dir: 0, steps: 0}

  defp step(%{board: board, x: x, y: y, dir: dir, steps: steps} = ant) do
    i = y * @n + x
    # A square off the board reads as blank and keeps no ink.
    inked = MapSet.member?(board, i)
    dir = band(dir + if(inked, do: 3, else: 1), 3)

    board =
      cond do
        i < 0 or i >= @n * @n -> board
        inked -> MapSet.delete(board, i)
        true -> MapSet.put(board, i)
      end

    {dx, dy} = elem({{0, -1}, {1, 0}, {0, 1}, {-1, 0}}, dir)
    %{ant | board: board, x: x + dx, y: y + dy, dir: dir, steps: steps + 1}
  end

  defp run(%{steps: steps} = ant, want) when steps < want, do: run(step(ant), want)
  defp run(ant, _want), do: ant

  defp target(p) do
    k = Enum.find(1..(tuple_size(@keys) - 1), &(elem(elem(@keys, &1), 0) >= p))
    {p0, s0} = elem(@keys, k - 1)
    {p1, s1} = elem(@keys, k)
    JSMath.round(s0 + (s1 - s0) * (p - p0) / (p1 - p0))
  end

  @impl true
  def frame(%{cells: cells} = state, t, _env) do
    p = JSMath.mod(t, @period)
    want = target(p)
    ant = if want < state.steps, do: Map.merge(state, reset()), else: state
    ant = run(ant, want)
    %{board: board, x: x, y: y} = ant

    fade =
      if p > @fade_from and p <= @fade_to,
        do: (p - @fade_from) / (@fade_to - @fade_from),
        else: 0

    ac = div(@n, 2) + @x0 - x
    ar = floor((y - div(@n, 2) - @y0) / 2)

    lines =
      for {row, r} <- Enum.with_index(cells) do
        for {{a, b, fa, fb}, c} <- Enum.with_index(row) do
          if c == ac and r == ar and fade == 0 do
            "@"
          else
            top = if MapSet.member?(board, a) and fa >= fade, do: 1, else: 0
            bottom = if MapSet.member?(board, b) and fb >= fade, do: 2, else: 0
            elem(@glyph, top + bottom)
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, ant}
  end
end
