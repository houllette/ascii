defmodule AsciiArt.Pieces.RuledMountains do
  @moduledoc """
  Ruled lines with a range rising from them, drifting forward.

  Ruled lines with a range rising out of their middle, drawn in the three
  strokes ASCII mountains use, _ / \\. Each line hides what it rises over,
  and the peaks drift slowly from the back lines to the front.

  Ported from `src/pieces/ruled-mountains.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "ruled mountains",
    category: :nature,
    note: "ruled lines with a range rising from them, drifting forward",
    cols: 64,
    rows: 20,
    fps: 10
  }

  @cols 64
  @rows 20
  @mid 64 / 2
  # Ruled lines, back to front, and rows between neighbouring lines.
  @n 6
  @gap 3
  # The tallest peak on each line, in rows: nearer stands taller.
  @amp {5, 5.5, 6, 6.6, 7.2, 8}
  # Lines a second the peaks come forward; seconds into the drift where t = 0
  # falls; a line seen for fewer cells than @sliver between nearer peaks is
  # left out.
  @speed 0.2
  @start 30
  @sliver 3

  # Each peak keeps to its lane, so the range stays balanced: {lane, in
  # columns from the middle, how far it wanders, its height against the
  # line's tallest, rows of steep flank west and east before it eases to a
  # shoulder, and where a lesser summit sits on its flank, 0 for none}. The
  # rest set its wandering.
  @peaks [
    {-16, 3, 0.55, 2, 1, 0, 0.71, 0.4, 0.93, 1.9},
    {-5, 3, 0.85, 3, 2, -4, 0.53, 2.6, 1.21, 4.1},
    {6, 3, 1, 2, 4, 5, 0.97, 4.4, 0.67, 0.3},
    {18, 3, 0.6, 3, 2, 0, 0.61, 1.2, 1.07, 5.2}
  ]

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options), do: nil

  # A peak's height at distance d from its summit: a row a column down its
  # steep upper flank, then half that, a _/ shoulder, to the foot.
  defp tent(h, d, steep) when d < steep, do: h - d
  defp tent(h, d, steep), do: h - (steep + (d - steep) / 2)

  # Whole-row heights along a line at column edges, the shape the peaks take
  # at drift s, all of them under one envelope.
  defp profile(s, amp) do
    shapes =
      for {lane, wander, tall, west, east, sub, fm, pm, fa, pa} <- @peaks do
        {@mid + lane + wander * :math.sin(fm * s + pm),
         amp * tall * (0.55 + 0.45 * :math.sin(fa * s + pa)), west, east, sub}
      end

    for x <- 0..@cols do
      f =
        Enum.reduce(shapes, 0, fn {m, h, west, east, sub}, f ->
          d = x - m
          y = tent(h, abs(d), if(d < 0, do: west, else: east))
          y = if sub != 0, do: max(y, tent(h - 2, abs(d - sub), 1.5)), else: y
          if y > f, do: y, else: f
        end)

      max(0, JSMath.round(f))
    end
    |> List.to_tuple()
  end

  @impl true
  def frame(state, t, env) do
    # Stipple is ink: on a light page it marks the shaded east flanks, on a
    # dark one the lit west flanks.
    shade = if env.paper, do: -1, else: 1
    horizon = List.to_tuple(List.duplicate(@rows, @cols))

    # Front to back, so each line only draws where nothing nearer has.
    {g, _owner, _horizon} =
      Enum.reduce((@n - 1)..0//-1, {%{}, %{}, horizon}, fn i, acc ->
        line(acc, i, t, shade)
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(g, {r, c}, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp line({g, owner, horizon}, i, t, shade) do
    base = @rows - 1 - (@n - 1 - i) * @gap
    # Line i takes the shape line i - 1 had 1 / @speed seconds ago.
    e = profile((i - (@start + t) * @speed) * 0.9, elem(@amp, i))

    # Where this line shows over everything nearer, column by column.
    seen =
      List.to_tuple(
        for c <- 0..(@cols - 1) do
          a = elem(e, c)
          b = elem(e, c + 1)
          r = base - max(a, b) + if(a == b, do: 0, else: 1)
          if r >= 0 and r < elem(horizon, c), do: r, else: -1
        end
      )

    Enum.reduce(0..(@cols - 1), {g, owner, horizon}, fn c, acc ->
      r = elem(seen, c)
      if r < 0, do: acc, else: stroke(acc, i, c, r, seen, e, base, shade)
    end)
  end

  defp stroke({g, owner, horizon}, i, c, r, seen, e, base, shade) do
    n = run_from(seen, c, -1)
    m = run_from(seen, c, 1)
    a = elem(e, c)
    b = elem(e, c + 1)
    below = elem(horizon, c)

    ch =
      cond do
        b > a -> "/"
        b < a -> "\\"
        true -> "_"
      end

    horizon = put_elem(horizon, c, r)
    nearer? = fn k -> Map.get(owner, {r, k}, -1) > i end

    # A sliver of line between nearer peaks reads as a stray mark, and a
    # slope pressed against a nearer line's stroke as one doubled line.
    skip =
      (m - n + 1 < @sliver and n > 0 and m < @cols - 1) or
        (ch != "_" and (nearer?.(c - 1) or nearer?.(c + 1))) or
        (ch != "_" and
           Enum.any?([c - 2, c + 2], &(nearer?.(&1) and Map.get(g, {r, &1}, " ") == ch)))

    if skip do
      {g, owner, horizon}
    else
      g = Map.put(g, {r, c}, ch)
      owner = Map.put(owner, {r, c}, i)

      g =
        if JSMath.sign(b - a) == shade,
          do: Enum.reduce((r + 1)..min(base, below - 1)//1, g, &Map.put(&2, {&1, c}, ".")),
          else: g

      {g, owner, horizon}
    end
  end

  # The end of the run of shown cells through column c, going by step.
  defp run_from(seen, c, step) do
    next = c + step

    if next >= 0 and next < @cols and elem(seen, next) >= 0,
      do: run_from(seen, next, step),
      else: c
  end
end
