defmodule AsciiArt.Pieces.Voronoi do
  @moduledoc """
  Cells of ground nearest each drifting seed.

  The plane split into cells, each the ground nearest one drifting seed.
  Every border is a straight edge, drawn one stroke thick.

  Ported from `src/pieces/voronoi.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}

  @meta %AsciiArt.Meta{
    name: "voronoi",
    category: :generative,
    note: "cells of ground nearest each drifting seed",
    cols: 64,
    rows: 22,
    fps: 15,
    loop: 30
  }

  # A character cell, in ems.
  @cw 0.6
  @rh 1.2
  # Seconds for every seed to come back round.
  @period 30
  # Larger than any squared distance in the frame: upstream's Infinity.
  @far 1.0e308

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    x = cols * @cw
    y = rows * @rh

    # Homes on a staggered grid of 4, 5 and 4; each seed circles its home a
    # whole number of times a period, so the loop closes.
    {seeds, _} =
      [4, 5, 4]
      |> Enum.with_index()
      |> Enum.flat_map(fn {n, row} -> for i <- 0..(n - 1), do: {n, row, i} end)
      |> Enum.map_reduce(Int32.to_int32(7), fn {n, row, i}, rand ->
        {[a, b, c, d, e, f], rand} = draw(rand, 6)
        hx = (i + 0.5 + (a - 0.5) * 0.5) / n * x
        hy = (row + 0.5 + (b - 0.5) * 0.4) / 3 * y
        r = 2.2 + c * 1.4

        {{clamp(hx, r + 1, x - r - 1), clamp(hy, 0.8 * r + 0.8, y - 0.8 * r - 0.8), r,
          if(d < 0.5, do: 1, else: -1) * (1 + floor(e * 2)), f * 6.283}, rand}
      end)

    %{
      seeds: seeds,
      x: x,
      y: y,
      # Each cell's centre, in ems, with its row and column.
      centres:
        for(
          r <- 0..(rows - 1),
          c <- 0..(cols - 1),
          do: {(c + 0.5) * @cw, (r + 0.5) * @rh, rem(r + c, 2) == 1}
        )
    }
  end

  defp draw(rand, n) do
    Enum.map_reduce(1..n, rand, fn _, rand -> Int32.mulberry32(rand) end)
  end

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))

  @impl true
  def frame(%{seeds: seeds, centres: centres} = state, t, env) do
    %{cols: cols} = @meta
    a = 2 * :math.pi() * t / @period

    pts =
      for {hx, hy, r, turns, p} <- seeds do
        {hx + r * :math.cos(turns * a + p), hy + r * 0.8 * :math.sin(turns * a + p)}
      end

    # Shade each cell by how far it is from its seed toward the border: 0 at
    # the seed, 1 on the border.
    shade =
      centres
      |> Enum.map(fn {px, py, odd} -> shade(nearest(pts, px, py), odd, env.paper) end)
      |> List.to_tuple()

    pt = List.to_tuple(pts)
    n = tuple_size(pt)

    {marks, corners} =
      Enum.reduce(0..(n - 1), {%{}, []}, fn i, {marks, corners} ->
        borders(cell(state, pt, i), i, marks, corners)
      end)

    # On the row a flat edge's _ would take, so flat edges run into it.
    marks =
      corners
      |> Enum.reverse()
      |> Enum.reduce(marks, fn {x, y, _}, marks ->
        put(marks, floor(x / @cw), JSMath.round(y / @rh) - 1, "+")
      end)

    # Each seed, with the shading cleared either side so it stands alone.
    marks =
      Enum.reduce(pts, marks, fn {sx, sy}, marks ->
        c = floor(sx / @cw)
        r = floor(sy / @rh)

        [-1, 1]
        |> Enum.reduce(marks, fn d, marks ->
          if at(marks, shade, r * cols + c + d) in [":", "·"],
            do: put(marks, c + d, r, " "),
            else: marks
        end)
        |> put(c, r, "@")
      end)

    lines =
      for r <- 0..(@meta.rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(marks, r * cols + c, elem(shade, r * cols + c))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # The squared distances to the nearest seed and the next nearest.
  defp nearest(pts, px, py) do
    Enum.reduce(pts, {@far, @far}, fn {sx, sy}, {d1, d2} ->
      dx = px - sx
      dy = py - sy
      d = dx * dx + dy * dy

      cond do
        d < d1 -> {d, d1}
        d < d2 -> {d1, d}
        true -> {d1, d2}
      end
    end)
  end

  # Two seeds on one spot make 0 / 0, NaN, which no level takes.
  defp shade({_d1, d2}, _odd, _paper) when d2 == 0, do: " "

  defp shade({d1, d2}, odd, paper) do
    f = :math.sqrt(d1 / d2)
    # On paper the light is the ground, so the seed is clear and the rim
    # takes the tone, stopping short of the border.
    case level(f, paper) do
      3 -> ":"
      2 -> "·"
      1 when odd -> "·"
      _ -> " "
    end
  end

  defp level(f, true) when f < 0.45, do: 0
  defp level(f, true) when f < 0.62, do: 1
  defp level(f, true) when f < 0.84, do: 2
  defp level(_f, true), do: 0
  defp level(f, false) when f < 0.22, do: 3
  defp level(f, false) when f < 0.42, do: 2
  defp level(f, false) when f < 0.62, do: 1
  defp level(_f, false), do: 0

  defp at(marks, shade, k) when k >= 0 and k < tuple_size(shade),
    do: Map.get(marks, k, elem(shade, k))

  defp at(_marks, _shade, _k), do: nil

  defp put(marks, c, r, ch) do
    %{cols: cols, rows: rows} = @meta

    if c >= 0 and c < cols and r >= 0 and r < rows,
      do: Map.put(marks, r * cols + c, ch),
      else: marks
  end

  # The cell of seed i: the frame clipped by the half plane nearer i than j,
  # for every j. Each vertex remembers which neighbour made the edge after it.
  defp cell(%{x: x, y: y}, pt, i) do
    {sxi, syi} = elem(pt, i)

    Enum.reduce(0..(tuple_size(pt) - 1), [{0, 0, -1}, {x, 0, -1}, {x, y, -1}, {0, y, -1}], fn
      _j, [] ->
        []

      ^i, poly ->
        poly

      j, poly ->
        {sxj, syj} = elem(pt, j)
        nx = sxj - sxi
        ny = syj - syi
        c = nx * (sxi + sxj) / 2 + ny * (syi + syj) / 2
        clip(poly, nx, ny, c, j)
    end)
  end

  defp clip([first | rest] = poly, nx, ny, c, j) do
    poly
    |> Enum.zip(rest ++ [first])
    |> Enum.flat_map(fn {{ax, ay, ak} = a, {bx, by, _}} ->
      da = ax * nx + ay * ny - c
      db = bx * nx + by * ny - c
      a_in = da <= 0
      kept = if a_in, do: [a], else: []

      if a_in != db <= 0 do
        f = da / (da - db)
        kept ++ [{ax + (bx - ax) * f, ay + (by - ay) * f, if(a_in, do: j, else: ak)}]
      else
        kept
      end
    end)
  end

  # Edges to seeds after this one are drawn here; a corner between two seed
  # edges, inside the frame, is a junction.
  defp borders([], _i, marks, corners), do: {marks, corners}

  defp borders([first | rest] = poly, i, marks, corners) do
    prevs = [List.last(poly) | Enum.drop(poly, -1)]
    nexts = rest ++ [first]

    [poly, nexts, prevs]
    |> Enum.zip()
    |> Enum.reduce({marks, corners}, fn {{px, py, j} = p, {qx, qy, _}, {_, _, prev}},
                                        {marks, corners} ->
      marks = if j > i, do: edge(marks, px / @cw, py / @rh, qx / @cw, qy / @rh), else: marks

      corners =
        if j >= 0 and prev >= 0 and i < j and i < prev, do: [p | corners], else: corners

      {marks, corners}
    end)
  end

  # An edge in cell units. Steep ones get a stroke a row, | or a slash where
  # they step a column; flat ones a stroke a column, _ or a slash where they
  # step a row, so the line never doubles or breaks.
  defp edge(marks, x0, y0, x1, y1) do
    cond do
      # A point, not an edge: upstream's 0 / 0 slope plots nothing.
      x0 == x1 and y0 == y1 -> marks
      abs(x1 - x0) <= abs(y1 - y0) and y1 < y0 -> steep(marks, x1, y1, x0, y0)
      abs(x1 - x0) <= abs(y1 - y0) -> steep(marks, x0, y0, x1, y1)
      x1 < x0 -> flat(marks, x1, y1, x0, y0)
      true -> flat(marks, x0, y0, x1, y1)
    end
  end

  defp steep(marks, x0, y0, x1, y1) do
    k = (x1 - x0) / (y1 - y0)

    ceil(y0 - 0.5)
    |> Stream.iterate(&(&1 + 1))
    |> Enum.take_while(&(&1 + 0.5 <= y1))
    |> Enum.reduce(marks, fn r, marks ->
      xa = x0 + k * (r - y0)
      xb = x0 + k * (r + 1 - y0)

      ch =
        cond do
          floor(xa) == floor(xb) -> "|"
          k > 0 -> "\\"
          true -> "/"
        end

      put(marks, floor(x0 + k * (r + 0.5 - y0)), r, ch)
    end)
  end

  defp flat(marks, x0, y0, x1, y1) do
    k = (y1 - y0) / (x1 - x0)
    first = ceil(x0 - 0.5)

    first
    |> Stream.iterate(&(&1 + 1))
    |> Enum.take_while(&(&1 + 0.5 <= x1))
    |> Enum.reduce(marks, fn c, marks ->
      # The end columns take the level of the corner they run into.
      la = JSMath.round(if c == first, do: y0, else: y0 + k * (c - x0))
      lb = JSMath.round(if c + 1.5 > x1, do: y1, else: y0 + k * (c + 1 - x0))

      cond do
        la == lb -> put(marks, c, la - 1, "_")
        lb < la -> put(marks, c, lb, "/")
        true -> put(marks, c, la, "\\")
      end
    end)
  end
end
