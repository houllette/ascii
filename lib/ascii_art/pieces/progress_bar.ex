defmodule AsciiArt.Pieces.ProgressBar do
  @moduledoc """
  Five bar styles filling at uneven paces, percent at right.

  Five progress bar styles stacked. Each fills at its own uneven pace, easing
  into short stalls the way real jobs do, holds at 100%, restarts.

  ## Options

    * `labels` - each bar's label (upstream's).

  This port's additions, for a terminal UI showing real progress:

    * `values` - a percentage for each bar, 0 to 100: one bar for each, up
      to 32, shown as given rather than played, the five styles taking
      turns. Update them as work goes with `AsciiArt.put_options/2`.
    * `style` - one of the five styles, 0 to 4, for every bar (by default
      each bar has its own, in turn).
    * `cols` - the frame's width, 24 to 200; the bars take all but 20 of it.

  The frame is two rows a bar and one more.

  Ported from `src/pieces/progress-bar.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}

  @meta %AsciiArt.Meta{
    name: "progress bar",
    category: :ui,
    note: "five bar styles filling at uneven paces, percent at right",
    cols: 48,
    rows: 11,
    fps: 30,
    options: %{
      labels: ["fetching", "unpacking", "indexing", "building", "linking"],
      values: [],
      style: nil,
      cols: 48
    },
    bounds: %{style: {0, 4}, cols: {24, 200}},
    shapes: %{values: [0.0]}
  }

  # Every bar is the frame's width but this many cells, ends included.
  @margin 20
  @eighths {" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"}
  # Seconds a full bar stays full, and an empty one waits before the next run.
  @hold 1.1
  @rest 0.4
  # Each bar's run length and where it starts, so frame 0 shows them part way.
  @fill {4.2, 3.4, 5.6, 3.8, 4.8}
  @phase {2.9, 0.7, 4.6, 1.6, 1.9}

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{values: values, cols: cols}), do: {trunc(cols), 2 * bars(values) + 1}

  # Upstream's five, or one a value, up to @most.
  @most 32
  defp bars([]), do: 5
  defp bars(values), do: min(length(values), @most)

  @impl true
  def init(%{labels: labels, values: values, style: style} = options) do
    {cols, rows} = size(options)
    values = Enum.take(values, @most)
    style = style && trunc(style)
    %{labels: labels, values: values, style: style, cols: cols, rows: rows, w: cols - @margin}
  end

  @impl true
  def frame(%{labels: labels, cols: cols, w: w} = state, t, _env) do
    blank = String.duplicate(" ", cols)
    bars = bars(state.values)

    lines =
      for r <- 0..(state.rows - 1) do
        i = div(r - 1, 2)

        if rem(r, 2) == 0 or i >= bars do
          blank
        else
          {p, percent} = reading(state.values, i, t)
          label = labels |> Enum.at(i, "") |> String.slice(0, 9) |> String.pad_trailing(10)
          pct = String.pad_leading("#{percent}%", 4)

          String.pad_trailing(
            "  " <> label <> draw(state.style || rem(i, 5), w, p) <> "  " <> pct,
            cols
          )
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # Upstream's run, or the value given: its fraction, and the percent shown
  # (from the value itself, which p * 100 could round below).
  defp reading([], i, t) do
    p = progress(i, t)
    {p, JSMath.floor(p * 100)}
  end

  defp reading(values, i, _t) do
    v = values |> Enum.at(i) |> max(0) |> min(100)
    {v / 100, JSMath.floor(v)}
  end

  # Each style draws progress p (0 to 1) in exactly w cells.
  defp draw(0, w, p) do
    n = JSMath.floor(p * (w - 2))
    "[" <> dup("=", n) <> if(n < w - 2, do: ">" <> dup(" ", w - 3 - n), else: "") <> "]"
  end

  defp draw(1, w, p) do
    e = JSMath.round(p * (w - 2) * 8)
    n = Int32.sar(e, 3)
    tail = if n < w - 2, do: elem(@eighths, Int32.band(e, 7)) <> dup(" ", w - 3 - n), else: ""
    "▕" <> dup("█", n) <> tail <> "▏"
  end

  defp draw(2, w, p) do
    n = JSMath.floor(p * (w - 2))
    "[" <> dup("#", n) <> dup(".", w - 2 - n) <> "]"
  end

  defp draw(3, w, p) do
    # Lamps that light in whole steps: fourteen in upstream's 28 cells.
    lamps = div(w, 2)
    n = JSMath.floor(p * lamps + 1.0e-9)
    String.slice(dup("█ ", n) <> dup("░ ", lamps - n), 0, w - 1) <> " "
  end

  defp draw(4, w, p) do
    h = JSMath.floor(p * w * 2)
    n = Int32.sar(h, 1)

    tail =
      if n < w,
        do: if(Int32.band(h, 1) == 1, do: "╾", else: "─") <> dup("─", w - 1 - n),
        else: ""

    dup("━", n) <> tail
  end

  defp dup(s, n), do: String.duplicate(s, max(n, 0))

  defp ease(x), do: x * x * (3 - 2 * x)

  defp progress(i, t) do
    fill = elem(@fill, i)
    cycle = fill + @hold + @rest
    tt = t + elem(@phase, i)
    k = JSMath.floor(tt / cycle)
    u = tt - k * cycle

    cond do
      u >= fill + @hold ->
        0

      u >= fill ->
        1

      true ->
        x = u / fill
        knots = knots(i, k)
        j = Enum.find(1..(tuple_size(knots) - 1), &(elem(elem(knots, &1), 0) >= x))
        {u0, v0} = elem(knots, j - 1)
        {u1, v1} = elem(knots, j)
        v0 + (v1 - v0) * ease((x - u0) / (u1 - u0))
    end
  end

  # One run: a few legs, each eased in and out, so the bar surges and stalls.
  defp knots(i, k) do
    {r, s} = Int32.mulberry32(i * 7919 + k * 104_729 + 17)
    legs = 4 + JSMath.floor(r * 3)

    {pairs, _} =
      Enum.map_reduce(1..legs, s, fn _, s ->
        {a, s} = Int32.mulberry32(s)
        {b, s} = Int32.mulberry32(s)
        {{0.5 + a, 0.2 + b}, s}
      end)

    {dt, dv} = Enum.unzip(pairs)
    st = Enum.reduce(dt, &(&2 + &1))
    sv = Enum.reduce(dv, &(&2 + &1))

    {points, _} =
      Enum.map_reduce(pairs, {0, 0}, fn {a, b}, {u, v} ->
        u = u + a / st
        v = v + b / sv
        {{u, v}, {u, v}}
      end)

    List.to_tuple([{0, 0} | List.replace_at(points, legs - 1, {1, 1})])
  end
end
