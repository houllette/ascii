defmodule AsciiArt.Pieces.DnaHelix do
  @moduledoc """
  A double helix with base pairs, turning about its axis.

  A double helix seen side on, turning about its own axis. The near half of
  each backbone is drawn heavy and the far half dotted, with base pairs between
  them, and the grooves alternate wide and narrow as in B-DNA.

  Ported from `src/pieces/dna-helix.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  @meta %AsciiArt.Meta{
    name: "dna helix",
    category: :shapes,
    note: "a double helix with base pairs, turning about its axis",
    cols: 64,
    rows: 15,
    fps: 20
  }

  @cols 64
  @rows 15
  # Radius in rows; a cell is twice as tall as it is wide.
  @a 5
  # Columns a turn.
  @pitch 42
  @k 2 * :math.pi() / @pitch
  # The second backbone trails the first by this, not by half a turn.
  @groove 0.64 * :math.pi()
  # Columns between base pairs, ten and a half a turn.
  @pair 4
  # Radians a second, and the angle at t = 0.
  @speed 0.5
  @a0 2.2
  # Columns left clear at each end: the molecule runs from column lo to hi.
  @end_gap 3
  @lo @end_gap
  @hi @cols - 1 - @end_gap
  @first_pair @lo + 3 + Bitwise.bsr(rem(@hi - @lo - 6, @pair), 1)

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options), do: nil

  @impl true
  def frame(state, t, _env) do
    a = @a0 + @speed * t

    # Base pairs first, each from one backbone to the other at the same place
    # on the axis: | in front of it, : behind. None in the last few columns,
    # so the ends thin out.
    g = Enum.reduce(@first_pair..(@hi - 3)//@pair, %{}, &base_pair(&2, &1, a))

    g = g |> backbone(0, a) |> backbone(1, a)

    # Behind a near backbone, the far one breaks for a cell all round.
    lines =
      for r <- 0..(@rows - 1) do
        for col <- 0..(@cols - 1), do: cell(g, r, col)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # Backbone s at column x: its row, its depth from -1 behind the axis to 1 in
  # front, and the row of the crest it is nearest. Rows run down the page, so
  # this winds right-handed.
  defp at(x, s, a) do
    th = @k * (x - @cols / 2) - a - s * @groove
    c = :math.cos(th)
    {@rows / 2 + @a * c, -:math.sin(th), @rows / 2 + if(c > 0, do: @a, else: -@a)}
  end

  defp y_at(x, s, a) do
    th = @k * (x - @cols / 2) - a - s * @groove
    @rows / 2 + @a * :math.cos(th)
  end

  defp base_pair(g, col, a) do
    {y0, z0, _} = at(col + 0.5, 0, a)
    {y1, z1, _} = at(col + 0.5, 1, a)
    r0 = floor(min(y0, y1))
    r1 = floor(max(y0, y1))

    Enum.reduce((r0 + 1)..(r1 - 1)//1, g, fn r, g ->
      u = (r + 0.5 - y0) / (y1 - y0)
      z = z0 + u * (z1 - z0)
      put(g, col, r, z, if(z > 0, do: "|", else: ":"), 2)
    end)
  end

  # Each column cuts each backbone once. Behind the axis it is a dot. In
  # front, a climbing stretch is / or \, two cells to a row, and the flat
  # top of a crest is a run of _ on the foot of the crest's row.
  defp backbone(g, s, a) do
    {cuts, g} =
      Enum.map_reduce(@lo..@hi, g, fn col, g ->
        {y, z, crest} = at(col + 0.5, s, a)
        dy = y_at(col + 1, s, a) - y_at(col, s, a)
        row = floor(y)
        cap = floor(crest - 0.25)

        cond do
          z < -0.2 ->
            {{col, row, y, z, 0}, put(g, col, row, z, "·", 1)}

          abs(dy) >= 0.3 and not (crest < y and row == cap) ->
            steep = if dy > 0, do: 1, else: -1
            {{col, row, y, z, steep}, put(g, col, row, z + 0.5, slash(steep), 0)}

          true ->
            {{col, row, y, z, 0}, put(g, col, cap, z + 0.5, "_", 0)}
        end
      end)

    rows = Map.new(cuts, fn {col, row, _, _, _} -> {col, row} end)

    # A climbing stretch alone in its row takes a second cell, on the side
    # where the line crosses the middle of the row.
    Enum.reduce(cuts, g, fn {col, row, y, z, steep}, g ->
      if steep == 0 or Map.get(rows, col - 1, -1) == row or Map.get(rows, col + 1, -1) == row or
           z < 0.3 do
        g
      else
        side = if (row + 0.5 - y) * steep > 0, do: 1, else: -1
        put(g, col + side, row, z + 0.5, slash(steep), 0)
      end
    end)
  end

  defp slash(1), do: "\\"
  defp slash(-1), do: "/"

  # Who drew a cell: 0 a near backbone, 1 a far one, 2 a base pair.
  defp put(g, col, r, _z, _ch, _who) when r < 0 or r >= @rows or col < @lo or col > @hi, do: g

  defp put(g, col, r, z, ch, who) do
    i = r * @cols + col

    case g do
      %{^i => {_, d, _}} when z <= d -> g
      _ -> Map.put(g, i, {ch, z, who})
    end
  end

  defp cell(g, r, col) do
    i = r * @cols + col

    case g do
      %{^i => {ch, _, 1}} -> if behind_near?(g, r, col), do: " ", else: ch
      %{^i => {ch, _, _}} -> ch
      _ -> " "
    end
  end

  defp behind_near?(g, r, col) do
    Enum.any?(
      for(
        dc <- -1..1,
        dr <- -1..1,
        r + dr >= 0 and r + dr < @rows,
        do: (r + dr) * @cols + col + dc
      ),
      fn j -> match?(%{^j => {_, d, 0}} when d > 0.6, g) end
    )
  end
end
