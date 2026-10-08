defmodule AsciiArt.Pieces.Sparkline do
  @moduledoc """
  Three live block sparklines scrolling left, values at right.

  Live metrics as one-row block sparklines, scrolling left as new samples
  arrive, each with its label, its latest value and the span's range.

  A series with `values` (a list of numbers) shows the newest of them;
  without, it plays a sample signal. `lo` and `hi` fix the scale (else it fits
  what is shown), `unit` and `digits` format the value. Up to five series fit,
  spaced a row apart when there are three or fewer. Without `range` the min
  and max columns go and the lines grow longer. `rate` is samples a second,
  which labels the time axis. Upstream's `format` function is not supported:
  options are data.

  For a terminal UI, give each series its `values` and update them as samples
  come (`AsciiArt.put_options/2`); this port also takes `cols`, the frame's
  width, 40 to 200 (the lines take what the label, value and range leave),
  and `rows`, 3 to 32, never fewer than the series and their header and axis
  need.

  Ported from `src/pieces/sparkline.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Text

  @meta %AsciiArt.Meta{
    name: "sparkline",
    category: :data,
    note: "three live block sparklines scrolling left, values at right",
    cols: 72,
    rows: 9,
    fps: 12,
    options: %{
      series: [
        %{label: "cpu", unit: "%", lo: 0, hi: 100},
        %{label: "memory", unit: " gb", lo: 1.2, hi: 3.4, digits: 1},
        %{label: "requests", unit: "/s", lo: 0, hi: 260}
      ],
      range: true,
      rate: 4,
      cols: 72,
      rows: 9
    },
    bounds: %{rate: {0, 100}, cols: {40, 200}, rows: {3, 32}},
    shapes: %{
      series: [%{label: "", unit: "", lo: 0.0, hi: 0.0, digits: 0, values: [0.0]}]
    }
  }

  @bars {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
  # Label, value and min/max widths; rows the series share.
  @lw 10
  @vw 7
  @rw 5
  @slots 5

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{cols: cols, rows: rows, series: series}) do
    {_gap, span} = span(Enum.take(series, @slots))
    {trunc(cols), max(trunc(rows), span + 2)}
  end

  # The series a `gap` of rows apart, `span` rows in all.
  defp span(series) do
    gap = if length(series) <= 3, do: 2, else: 1
    {gap, (max(1, length(series)) - 1) * gap + 1}
  end

  @impl true
  def init(%{series: series, range: range, rate: rate} = options) do
    {cols, rows} = size(options)
    rate = max(0.05, if(rate == 0, do: @meta.options.rate, else: rate))
    x0 = 2 + @lw
    # Samples on screen.
    w = cols - x0 - 2 - @vw - if(range, do: 2 + @rw + 1 + @rw, else: 0) - 2
    series = Enum.take(series, @slots)
    # The header, the series and the time axis sit centred as one block.
    {gap, span} = span(series)
    top = JSMath.floor((rows - span - 2) / 2) + 1
    blank = String.duplicate(" ", cols)

    header =
      if range,
        do:
          fit(
            String.duplicate(" ", x0 + w + 2 + @vw + 2) <>
              Text.pad_start("min", @rw) <> " " <> Text.pad_start("max", @rw),
            cols
          ),
        else: blank

    ago = JSMath.to_string(JSMath.round(w / rate)) <> "s ago"
    axis = fit(String.duplicate(" ", x0) <> Text.pad_end(ago, w - 2) <> "now", cols)

    lines =
      List.duplicate(blank, rows)
      |> List.replace_at(top - 1, header)
      |> List.replace_at(top + span, axis)

    fresh = reset(series, w)
    start = fill(fresh, w * 2, w)

    %{
      cols: cols,
      series: series,
      range: range,
      rate: rate,
      w: w,
      gap: gap,
      top: top,
      lines: lines,
      fresh: fresh,
      start: start,
      sim: start
    }
  end

  defp fit(s, cols), do: s |> Text.slice(0, cols) |> Text.pad_end(cols)

  # A ring of the last W samples per signal; play time decides how many exist.
  defp reset(series, w) do
    rings =
      series
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        if Map.has_key?(s, :values),
          do: nil,
          else: %{
            kind: rem(i, 3),
            ring: List.to_tuple(List.duplicate(0.0, w)),
            rand: 911 + i * 7919,
            v: 0.4,
            busy: 0,
            cap: 0.82,
            n: 0
          }
      end)

    %{made: 0, rings: rings}
  end

  defp fill(%{made: made} = sim, need, _w) when made >= need, do: sim

  defp fill(%{made: made, rings: rings}, need, w) do
    rings =
      Enum.map(rings, fn
        nil ->
          nil

        sig ->
          sig = signal(sig)
          %{sig | ring: put_elem(sig.ring, rem(made, w), JSMath.fround(sig.v))}
      end)

    fill(%{made: made + 1, rings: rings}, need, w)
  end

  defp next(sig) do
    {x, rand} = Int32.mulberry32(sig.rand)
    {x, %{sig | rand: rand}}
  end

  # Sample signals, each 0..1 from its own seeded state, scaled into lo..hi.
  # Mostly idle, with bursts of work that come and go.
  defp signal(%{kind: 0} = s) do
    {s, busy} =
      if s.busy > 0 do
        {s, s.busy - 1}
      else
        {x, s} = next(s)

        if x < 0.06,
          do: with({y, s} <- next(s), do: {s, 4 + JSMath.floor(y * 9)}),
          else: {s, s.busy}
      end

    {z, s} = next(s)
    v = s.v + ((if(busy != 0, do: 0.78, else: 0.22) - s.v) * 0.55 + (z - 0.5) * 0.3)
    %{s | busy: busy, v: max(0.02, min(0.99, v))}
  end

  # A heap that fills unevenly and falls back when it is collected.
  defp signal(%{kind: 1} = s) do
    {x, s} = next(s)
    v = s.v + (0.01 + x * 0.035)

    if v > s.cap do
      {a, s} = next(s)
      {b, s} = next(s)
      %{s | v: 0.1 + a * 0.14, cap: 0.73 + b * 0.22}
    else
      %{s | v: v}
    end
  end

  # A slow swell in traffic with jitter on every sample.
  defp signal(%{kind: 2} = s) do
    base = 0.48 + 0.27 * :math.sin(s.n / 14)
    {a, s} = next(s)
    {b, s} = next(s)
    v = s.v + ((base - s.v) * 0.7 + (a + b - 1) * 0.23)
    %{s | n: s.n + 1, v: max(0.015, min(1, v))}
  end

  @impl true
  def frame(%{w: w} = state, t, _env) do
    need = w * 2 + JSMath.floor(t * state.rate)
    # Upstream starts over when asked for fewer samples than it has made.
    from = if need < state.sim.made, do: rewind(state, need), else: state.sim
    sim = fill(from, need, w)

    lines =
      state.series
      |> Enum.zip(sim.rings)
      |> Enum.with_index()
      |> Enum.reduce(state.lines, fn {{s, sig}, i}, lines ->
        List.replace_at(
          lines,
          state.top + i * state.gap,
          fit(line(s, window(s, sig, sim.made, w), state), state.cols)
        )
      end)

    {Enum.intersperse(lines, ?\n), nil, %{state | sim: sim}}
  end

  defp rewind(state, need), do: if(need >= state.start.made, do: state.start, else: state.fresh)

  # What is on screen, oldest first, in the series' own units.
  defp window(s, nil, _made, w), do: s |> Map.get(:values, []) |> Enum.take(-w)

  defp window(s, %{ring: ring}, made, w) do
    lo = Map.get(s, :lo) || 0
    hi = Map.get(s, :hi) || 100
    for j <- 0..(w - 1), do: lo + elem(ring, rem(made + j, w)) * (hi - lo)
  end

  defp line(s, [], %{w: w}) do
    "  " <> label(s) <> String.duplicate(" ", w) <> "▏ " <> Text.pad_start("", @vw)
  end

  defp line(s, win, %{w: w, range: range}) do
    {least, most} = Enum.min_max(win)
    lo = Map.get(s, :lo) || least
    hi = Map.get(s, :hi) || if(most > lo, do: most, else: lo + 1)
    d = if hi - lo == 0, do: 1, else: hi - lo

    bars =
      Enum.map(win, fn v ->
        elem(@bars, max(0, min(7, JSMath.round((v - lo) / d * 7))))
      end)

    value = s |> fmt(List.last(win), true) |> Text.pad_start(@vw)
    pad = String.duplicate(" ", w - length(win))
    line = IO.chardata_to_string(["  ", label(s), pad, bars, "▏ ", value])

    if range,
      do:
        line <>
          "  " <>
          Text.pad_start(fmt(s, least, false), @rw) <>
          " " <> Text.pad_start(fmt(s, most, false), @rw),
      else: line
  end

  defp label(s), do: (Map.get(s, :label) || "") |> Text.slice(0, @lw - 1) |> Text.pad_end(@lw)

  # JS's toFixed takes 0 to 100 digits and throws past them; here they are held to that range.
  defp fmt(s, v, unit?) do
    digits = (Map.get(s, :digits) || 0) |> trunc() |> max(0) |> min(100)
    JSMath.to_fixed(v, digits) <> if(unit?, do: Map.get(s, :unit) || "", else: "")
  end
end
