defmodule Ascii.Pieces.Fox do
  @moduledoc """
  A fox asleep on its tail, breathing, peeking now and then.

  A fox asleep, curled up with its chin on its tail. Its flank rises and
  falls; now and then it opens one eye and looks about, or flicks an ear.

  Ported from `src/pieces/fox.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Text

  @meta %Ascii.Meta{
    name: "fox",
    category: :creatures,
    note: "a fox asleep on its tail, breathing, peeking now and then",
    cols: 47,
    rows: 16,
    fps: 10
  }

  @cols 47
  @rows 16

  @fox [
    "           /\\          /\\",
    "          /  \\        /  \\",
    "         /    `.____.'    \\",
    "        /                  \\",
    "       ;    `-'      `-'    ;",
    "        `.     \\    /     .'`-.._",
    "     _.-' `-.   \\../   .-'       ``-._",
    "  .-'        `-. \\/ .-'               `.",
    " /   _..--''``-.`--'.-''``--..__        \\",
    "|  .'   ,                       ``-.     |",
    "| (    (                            `.   |",
    "|  `.   `.                            \\  |",
    " \\   `-..__                            \\ |",
    "  `-..__   ``---...______________...----'"
  ]
  # Where the drawing sits in the frame.
  @ox 2
  @oy 1

  # Seconds.
  @loop 12
  # Seconds a breath; the flank is out for the middle of it.
  @breath 4
  # Breathing in, the flank swells out a column: {row, col, glyphs} over the art.
  @swell [
    {7, 38, "`-."},
    {8, 40, " \\"},
    {9, 41, " |"},
    {10, 41, " |"},
    {11, 41, " |"},
    {12, 41, " |"},
    {13, 40, "-'"}
  ]
  @eye {4, 21}
  # One eye opens, looks one way and the other, and shuts: {from, to, glyphs, shift}.
  @peek [
    {2.2, 2.5, "`o'", 0},
    {2.5, 3.0, "(o)", 0},
    {3.0, 3.5, "(o)", -1},
    {3.5, 4.0, "(o)", 1},
    {4.0, 4.3, "(o)", 0},
    {4.3, 4.6, "`o'", 0}
  ]
  # The right ear's tip folds over.
  @ear [{7.0, 7.2}, {7.45, 7.65}]
  # Each z drifts up and away from the head a cell at a time, growing as it goes.
  @z_every 2
  @z_life 4
  @z_path {{4, 31}, {3, 32}, {3, 33}, {3, 34}, {2, 35}, {2, 36}, {2, 37}, {1, 38}, {1, 39},
           {1, 40}}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    {{first, _, _, _}, {_, last, _, _}} = {hd(@peek), List.last(@peek)}

    %{
      fox: @fox |> Enum.with_index() |> Enum.flat_map(fn {s, r} -> marks(r, 0, s) end),
      swell: Enum.flat_map(@swell, fn {r, c, s} -> marks(r, c, s) end),
      peek:
        Enum.map(@peek, fn {a, z, s, shift} ->
          {er, ec} = @eye
          {a, z, marks(er, ec - 1, "     ") ++ marks(er, ec + shift, s)}
        end),
      ear: marks(0, 23, "/-"),
      awake: {first - 0.3, last + 0.6},
      # k runs from -2 to ceil(LOOP / Z_EVERY).
      zs: -2..JSMath.ceil(@loop / @z_every)
    }
  end

  # Every character of s, spaces too, offset to where the drawing sits.
  defp marks(r, c, s) do
    for {ch, i} <- Enum.with_index(Text.chars(s)), do: {(@oy + r) * @cols + @ox + c + i, ch}
  end

  defp put(g, marks), do: Enum.reduce(marks, g, fn {i, ch}, g -> Map.put(g, i, ch) end)

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t, @loop) + @loop, @loop)
    b = JSMath.mod(u, @breath)

    g = put(%{}, state.fox)
    g = if b >= 0.6 and b < 2.4, do: put(g, state.swell), else: g

    g =
      case Enum.find(state.peek, fn {a, z, _} -> u >= a and u < z end) do
        {_, _, marks} -> put(g, marks)
        nil -> g
      end

    g = if Enum.any?(@ear, fn {a, z} -> u >= a and u < z end), do: put(g, state.ear), else: g
    g = zs(g, state, u)

    lines =
      for r <- 0..(@rows - 1) do
        base = r * @cols
        for c <- 0..(@cols - 1), do: Map.get(g, base + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # A z is only let out while both eyes are shut.
  defp zs(g, %{zs: zs, awake: {from, to}}, u) do
    Enum.reduce(zs, g, fn k, g ->
      born = k * @z_every
      age = u - born
      at = JSMath.mod(JSMath.mod(born, @loop) + @loop, @loop)

      if age < 0 or age >= @z_life or (at >= from and at < to) do
        g
      else
        i = JSMath.floor(age / @z_life * tuple_size(@z_path))
        {r, c} = elem(@z_path, i)
        Map.put(g, r * @cols + c, if(i < 6, do: "z", else: "Z"))
      end
    end)
  end
end
