defmodule AsciiArt.Pieces.Harmonograph do
  @moduledoc """
  A pen on two decaying pendulums winding a figure inward.

  A pen on two pendulums, one swinging across and one up and down, both
  slowly running down, so the figure winds in on itself to a dense centre.
  While the next figure starts, the last is lifted from the outside in.

  Ported from `src/pieces/harmonograph.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "harmonograph",
    category: :physics,
    note: "a pen on two decaying pendulums winding a figure inward",
    cols: 64,
    rows: 28,
    fps: 30,
    loop: 37.5
  }

  # A cell in em.
  @w 0.6
  @h 1.2
  # Pendulum time per sample, too short to skip a cell; pendulum time within
  # which the pen coming back to a cell is the same stroke.
  @step 0.0015
  @near 0.25
  # Seconds; the lift runs under the next figure's start.
  @draw 10
  @show 2.5
  @lift 3
  # The first figure, a little over half drawn.
  @start 6

  @cols 64
  @rows 28

  @impl true
  def meta, do: @meta

  # Swings across and up and down: frequency and phase each, how much faster
  # the up and down swing runs down, how many passes, and how far in it winds.
  defp figures do
    [
      %{fx: 1, px: :math.pi() / 2, fy: 1.02, py: 0, lean: 1.15, passes: 9, end: 0.12},
      %{fx: 2.006, px: 0, fy: 1, py: 0, lean: 1, passes: 6, end: 0.15},
      %{fx: 1, px: :math.pi() / 4, fy: 0.985, py: 0, lean: 0.9, passes: 8, end: 0.15}
    ]
  end

  @impl true
  def init(_options) do
    sheets = figures() |> Enum.map(&sheet/1) |> List.to_tuple()
    %{sheets: sheets}
  end

  # One figure, as every stroke the pen lays, in order: the cell, when, and
  # its mark.
  defp sheet(f) do
    stop = 2 * :math.pi() * f.passes
    n = JSMath.floor(stop / @step) + 1

    {points, {x0, x1, y0, y1}} =
      Enum.map_reduce(0..(n - 1), {0, 0, 0, 0}, fn i, {x0, x1, y0, y1} ->
        t = i * @step
        # Friction at the pivots takes the same off each swing, so the passes
        # come in evenly.
        a = 1 - (1 - f.end) * t / stop
        x = a * :math.sin(f.fx * t + f.px)
        y = -:math.pow(a, f.lean) * :math.sin(f.fy * t + f.py)
        {{x, y}, {min(x0, x), max(x1, x), min(y0, y), max(y1, y)}}
      end)

    # Centred in the frame, four fifths of it across and down.
    sx = (0.8 * @cols - 1) / (x1 - x0)
    sy = (0.8 * @rows - 0.6) / (y1 - y0)
    mx = (x0 + x1) / 2
    my = (y0 + y1) / 2

    points =
      Enum.map(points, fn {x, y} -> {@cols / 2 + (x - mx) * sx, @rows / 2 + (y - my) * sy} end)

    strokes = strokes(points)

    # A corner the pen only clipped is left blank.
    keep =
      for s <- strokes, s.len > 0.12, g = glyph(s), g != "", do: {s.t0, s.c, g}

    lifted =
      keep
      |> Enum.reduce(%{}, fn {t0, c, g}, acc -> Map.put(acc, c, {t0, g}) end)
      |> Enum.sort()
      |> Enum.map(fn {c, {t0, g}} -> {c, t0, g} end)

    pen = for {x, y} <- points, into: <<>>, do: <<JSMath.floor(y) * @cols + JSMath.floor(x)::16>>

    %{end: stop, pen: pen, samples: n, strokes: keep, lifted: lifted}
  end

  defp strokes([{px, py} | _] = points) do
    {strokes, _, _, _} =
      Enum.reduce(points, {%{}, %{}, {px, py}, 0}, fn {x, y}, {strokes, open, {px, py}, i} ->
        t = i * @step
        fx = JSMath.floor(x)
        fy = JSMath.floor(y)
        c = fy * @cols + fx
        lx = x - fx
        ly = y - fy

        {k, s, open} = stroke_at(strokes, open, c, t, lx, ly)

        s = %{
          s
          | len: s.len + JSMath.hypot((x - px) * @w, (y - py) * @h),
            t1: t,
            lx: lx,
            ly: ly,
            sum: s.sum + ly,
            n: s.n + 1,
            x0: min(s.x0, lx),
            x1: max(s.x1, lx),
            y0: min(s.y0, ly),
            y1: max(s.y1, ly)
        }

        {Map.put(strokes, k, s), open, {x, y}, i + 1}
      end)

    for k <- 0..(map_size(strokes) - 1), do: Map.fetch!(strokes, k)
  end

  # The stroke the pen is laying in cell c, or a new one if it was last
  # there too long ago.
  defp stroke_at(strokes, open, c, t, lx, ly) do
    with {:ok, k} <- Map.fetch(open, c),
         %{t1: t1} = s when t - t1 <= @near <- Map.fetch!(strokes, k) do
      {k, s, open}
    else
      _ ->
        k = map_size(strokes)

        s = %{
          c: c,
          t0: t,
          t1: t,
          ex: lx,
          ey: ly,
          lx: lx,
          ly: ly,
          x0: lx,
          x1: lx,
          y0: ly,
          y1: ly,
          sum: 0,
          n: 0,
          len: 0
        }

        {k, s, Map.put(open, c, k)}
    end
  end

  # The mark for one stroke through a cell, from where it came in and left
  # and how far it reached each way, all in cells. A stroke that turns back
  # across is a bracket, one that turns back up or down a flat mark at its
  # height.
  defp glyph(s) do
    m = 0.06
    right = s.x1 - max(s.ex, s.lx) > m
    left = min(s.ex, s.lx) - s.x0 > m
    turn_y = s.y1 - max(s.ey, s.ly) > m or min(s.ey, s.ly) - s.y0 > m
    span = s.y1 - s.y0
    dx = (s.lx - s.ex) * @w
    dy = (s.ly - s.ey) * @h

    cond do
      right != left and span * @h > 0.25 * (s.x1 - s.x0) * @w -> if right, do: ")", else: "("
      turn_y -> flat(s)
      # A steep line is drawn once a row, in the cell where it crosses the row's middle.
      abs(dx) < 0.35 * abs(dy) -> if s.y0 < 0.5 and s.y1 >= 0.5, do: "|", else: ""
      span < 0.45 -> flat(s)
      dx * dy > 0 -> "\\"
      true -> "/"
    end
  end

  defp flat(s) do
    mid = s.sum / s.n

    cond do
      mid < 0.3 -> "'"
      mid < 0.6 -> "-"
      mid < 0.82 -> "."
      true -> "_"
    end
  end

  @impl true
  def frame(%{sheets: sheets} = state, t, _env) do
    count = tuple_size(sheets)
    tt = @start + t
    period = @draw + @show
    idx = JSMath.floor(tt / period)
    local = tt - idx * period
    s = elem(sheets, rem(idx, count))

    # The last figure, lifted in the order it went down, outer swings first.
    out =
      if local < @lift do
        old = elem(sheets, rem(idx + count - 1, count))
        u = local / @lift * old.end
        for {c, w, g} <- old.lifted, w > u, into: %{}, do: {c, g}
      else
        %{}
      end

    tau = min(local, @draw) / @draw * s.end

    out =
      Enum.reduce_while(s.strokes, out, fn {t0, c, g}, out ->
        if t0 <= tau, do: {:cont, Map.put(out, c, g)}, else: {:halt, out}
      end)

    out =
      if local < @draw do
        j = min(s.samples - 1, JSMath.floor(tau / @step))
        <<c::16>> = binary_part(s.pen, j * 2, 2)
        Map.put(out, c, "o")
      else
        out
      end

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
