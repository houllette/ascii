defmodule Ascii.Pieces.ProgressBar do
  @moduledoc """
  Five bar styles filling at uneven paces, percent at right.

  Five progress bar styles stacked. Each fills at its own uneven pace, easing
  into short stalls the way real jobs do, holds at 100%, restarts. As
  upstream draws it, the bars play runs of their own; give it `values` and
  it shows your jobs' progress instead, for a dashboard or a terminal UI.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them, and values given are drawn as they are, so each new
  reading shows at once.

    * `values` - a percentage for each bar, 0 to 100 (outside it, held to
      it): one bar for each, up to 32, shown as given rather than played.
      Default `[]`: upstream's five bars, each filling at its own pace.
    * `labels` - each bar's label, in order, cut to 9 characters; a bar
      without one has none. Default `["fetching", "unpacking", "indexing",
      "building", "linking"]`.
    * `style` - one of the five styles, 0 to 4, for every bar: 0 `[===>  ]`,
      1 a smooth bar of eighth blocks, 2 `[###...]`, 3 lamps that light in
      whole steps, 4 a heavy line running on into a light one. Default
      `nil`: each bar its own, in turn.
    * `cols` - the frame's width, 24 to 200; the bars take all but 20 of
      it. Default 48. The frame is two rows a bar and one more.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `label` - a bar's label.
    * `frame` - a bar's ends where its style has them (brackets, or
      edges), grey.
    * `bar` - its filled cells (and the arrow head, the part filled cell, a
      half step), blue; `bar.done` when it reads 100%, green.
    * `track` - its empty cells, grey.
    * `value`, `unit` - the percent, its `%` grey.

  ## Keys and clicks

  It takes none: it shows progress, and `Ascii.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still
  tells your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): which bar's label, say.

  ## Screen readers

  `Ascii.describe/1` reads each bar's label and percent, as the bars
  show them: "progress: copying 42%, verifying 100%"; past eight bars,
  "and N more". Playing its own runs, it gives the piece's name and note.

  ## Example

  ```elixir
  options = %{values: [42, 100], labels: ["copying", "verifying"], style: 1}
  bars = Ascii.new!("progress-bar", options: options, parts: true)
  {frame, _bars} = Ascii.frame(bars, 0.0)
  {frame.cols, frame.rows}
  #=> {48, 5}

  Ascii.describe(bars)
  #=> "progress: copying 42%, verifying 100%"

  bars = Ascii.put_options!(bars, values: [80, 100])
  Ascii.describe(bars)
  #=> "progress: copying 80%, verifying 100%"
  ```

  ```heex
  <Ascii.Phoenix.live_player id="jobs" piece="progress-bar" options={%{values: @progress, labels: @jobs}} parts />
  ```

  Ported from `src/pieces/progress-bar.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}

  @meta %Ascii.Meta{
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
    shapes: %{values: [0.0]},
    parts: [
      {"label", nil},
      {"frame", "#8b949e"},
      {"bar", "#58a6ff"},
      {"bar.done", "#3fb950"},
      {"track", "#8b949e"},
      {"value", nil},
      {"unit", "#8b949e"}
    ]
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

  # This port's own: in words, each value given with its label, the percent
  # as the bar shows it; past eight, how many more.
  @impl true
  def describe(%{values: []}), do: nil

  def describe(%{labels: labels, values: values}) do
    values = Enum.take(values, @most)

    told =
      values
      |> Enum.take(8)
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {v, i} ->
        label = labels |> Enum.at(i, "") |> String.slice(0, 24)
        label = if label == "", do: "bar #{i + 1}", else: label
        "#{label} #{v |> max(0) |> min(100) |> JSMath.floor()}%"
      end)

    more = length(values) - 8
    "progress: " <> told <> if(more > 0, do: ", and #{more} more", else: "")
  end

  # This port's own: the parts of a frame. A bar's row is its label, as the
  # frame cuts it from the options, the bar in its w cells, and the percent.
  # Styles 0 to 2 have an end at each side of the bar, drawn like a filled
  # cell in style 1, so the ends go by place and the cells between by what
  # they are. Blank cells (a track drawn in spaces, the gaps between style
  # 3's lamps) are in no part.

  @reading ~r/^( +)(\d+)(%)( *)$/
  @filled ["=", ">", "#", "█", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "━", "╾"]
  @empty [".", "░", "─"]

  @impl true
  def parts(%{lines: lines}, %{labels: labels, values: values, style: style} = options) do
    {cols, _rows} = size(options)
    bars = bars(values)
    style = style && trunc(style)

    for {line, r} <- Enum.with_index(lines) do
      i = div(r - 1, 2)

      if rem(r, 2) == 0 or i >= bars,
        do: [{nil, line}],
        else: bar_parts(line, Enum.at(labels, i, ""), style || rem(i, 5), cols - @margin)
    end
  end

  defp bar_parts(line, label, style, w) do
    label = String.slice(label, 0, 9)
    lead = "  " <> String.pad_trailing(label, 10)

    with true <- String.starts_with?(line, lead),
         {cells, rest} = String.split_at(binary_slice(line, byte_size(lead)..-1//1), w),
         [_ | _] = reading <- Parts.captures(rest, @reading, [nil, "value", "unit", nil]) do
      fill = if {"value", "100"} in reading, do: "bar.done", else: "bar"
      pad = binary_slice(lead, (2 + byte_size(label))..-1//1)

      Parts.merge(
        [{nil, "  "}, {"label", label}, {nil, pad}] ++ cells(cells, style, fill) ++ reading
      )
    else
      _ -> [{nil, line}]
    end
  end

  defp cells(cells, style, fill) when style in 0..2 do
    {first, middle} = String.split_at(cells, 1)
    {middle, last} = String.split_at(middle, -1)
    [{"frame", first} | by_cell(middle, fill)] ++ [{"frame", last}]
  end

  defp cells(cells, _style, fill), do: by_cell(cells, fill)

  defp by_cell(cells, fill), do: Parts.chars(cells, &cell(&1, fill))

  defp cell(ch, fill) when ch in @filled, do: fill
  defp cell(ch, _fill) when ch in @empty, do: "track"
  defp cell(_ch, _fill), do: nil
end
