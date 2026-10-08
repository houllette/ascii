defmodule AsciiArt.Pieces.GliderGun do
  @moduledoc """
  Gosper's gun firing a glider every 30 generations.

  Gosper's glider gun in Conway's life, two cells to a character so every
  cell is square. It fires a glider every 30 generations, and an eater below
  the frame swallows each one, so the field repeats exactly.

  Ported from `src/pieces/glider-gun.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  @meta %AsciiArt.Meta{
    name: "glider gun",
    category: :generative,
    note: "gosper's gun firing a glider every 30 generations",
    cols: 56,
    rows: 20,
    fps: 10,
    loop: 3
  }

  @gun [
    "........................o",
    "......................o.o",
    "............oo......oo............oo",
    "...........o...o....oo............oo",
    "oo........o.....o...oo",
    "oo........o...o.oo....o.o",
    "..........o.....o.......o",
    "...........o...o",
    "............oo"
  ]
  @eater ["oo", "o", ".ooo", "...o"]
  @period 30

  @pad 4
  # The gun's top left in the picture, in cells.
  @gx 2
  @gy 2
  # How far down the glider lane the eater sits, past the frame.
  @k 30
  @w 56 + 2 * @pad + 8
  @h 20 * 2 + 2 * @pad + 8

  # One character holds a cell over the cell below it.
  @glyph {" ", "▀", "▄", "█"}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    live =
      MapSet.new(place(@gun, @gx, @gy) ++ place(@eater, @gx + 28 + @k, @gy + 15 + @k))

    # Run until the lane is full of gliders, then keep one period of frames.
    live = Enum.reduce(1..(4 * (@k + 40) + 60), live, fn _, live -> step(live) end)

    {cycle, _} =
      Enum.map_reduce(1..@period, live, fn _, live ->
        {IO.iodata_to_binary(text(live)), step(live)}
      end)

    List.to_tuple(cycle)
  end

  defp place(shape, x0, y0) do
    for {row, y} <- Enum.with_index(shape),
        {"o", x} <- row |> String.graphemes() |> Enum.with_index(),
        do: {@pad + x0 + x, @pad + y0 + y}
  end

  # The outer ring is never written, so it stays dead.
  defp step(live) do
    counts =
      Enum.reduce(live, %{}, fn {x, y}, counts ->
        for dy <- -1..1, dx <- -1..1, dx != 0 or dy != 0, reduce: counts do
          counts -> Map.update(counts, {x + dx, y + dy}, 1, &(&1 + 1))
        end
      end)

    for {{x, y} = cell, n} <- counts,
        x >= 1 and x < @w - 1 and y >= 1 and y < @h - 1,
        n == 3 or (n == 2 and MapSet.member?(live, cell)),
        into: MapSet.new(),
        do: cell
  end

  defp text(live) do
    %{cols: cols, rows: rows} = @meta
    bit = fn x, y -> if MapSet.member?(live, {x, y}), do: 1, else: 0 end

    lines =
      for r <- 0..(rows - 1) do
        y = @pad + 2 * r

        for c <- 0..(cols - 1) do
          x = @pad + c
          elem(@glyph, bit.(x, y) + 2 * bit.(x, y + 1))
        end
      end

    Enum.intersperse(lines, ?\n)
  end

  @impl true
  def frame(cycle, t, _env) do
    {elem(cycle, rem(floor(t * @meta.fps + 1.0e-6), @period)), nil, cycle}
  end
end
