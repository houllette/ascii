defmodule Ascii.Pieces.Sparkline do
  @moduledoc """
  Three live block sparklines scrolling left, values at right.

  Live metrics as one-row block sparklines, scrolling left as new samples
  arrive, each with its label, its latest value and the span's range. As
  upstream draws it, three made-up signals play; give each series its
  `values` and it shows yours.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`) as
  samples come: a series' `values` show as given, the newest at the right.
  `Ascii.Telemetry.sparkline/2` gives a series a metric from your app's
  telemetry, and `Ascii.BEAM.sparkline/2` this BEAM's memory, processes
  and run queue.

    * `series` - up to five, each a map of:
      * `label` - its name, on the left.
      * `values` - its samples, oldest first, up to 10^15 either way; the
        newest that fit show. Without, it plays a sample signal.
      * `lo`, `hi` - the scale's ends; without, it fits what is shown.
      * `unit`, `digits` - after the latest value, and its decimals.

      Spaced a row apart when there are three or fewer. Default upstream's
      cpu, memory and requests. Upstream's `format` function is not taken:
      options are data.
    * `range` - `false` drops the min and max columns, and the lines grow
      longer. Default `true`.
    * `rate` - samples a second, 0 to 100, which labels the time axis.
      Default 4.
    * `cols` - the frame's width, 40 to 200; the lines take what the label,
      value and range leave. Default 72.
    * `rows` - the frame's height, 3 to 32, never fewer than the series and
      their header and axis need. Default 9.

  A value too wide for its column, which upstream writes past it, is
  written to fit: with fewer decimals, then compactly, in thousands,
  millions and on (`17.5M`, `3.02G`; see `Ascii.Kit.Number`).

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `title` - the headings over the range, grey.
    * `label` - a series' name.
    * `spark` - the sparklines, blue, and `spark.1` to `spark.5`, one series
      each from the top: `spark.1` as `spark`, `spark.2` cyan, `spark.3`
      purple, `spark.4` pink, `spark.5` orange.
    * `axis` - the mark closing each line at now, grey.
    * `value`, `unit` - a series' latest value.
    * `value.min`, `value.max` - its range, grey.
    * `scale` - the time axis under them, grey.

  ## Keys and clicks

  It takes none: it shows samples, and `Ascii.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still tells
  your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): `spark.2`, say, for the second series.

  ## Screen readers

  `Ascii.describe/1` reads each series given values, its label and
  latest value: "sparkline: cpu 34%, memory 2.1 gb". With no series given
  values, it gives the piece's name and note.

  ## Example

  ```elixir
  cpu = %{label: "cpu", unit: "%", lo: 0, hi: 100, values: [12, 30, 25, 60]}
  spark = Ascii.new!("sparkline", options: %{series: [cpu], range: false, rows: 3}, parts: true)

  spark = Ascii.put_options!(spark, series: [%{cpu | values: cpu.values ++ [45]}])
  Ascii.describe(spark)
  #=> "sparkline: cpu 45%"

  {frame, _spark} = Ascii.frame(spark, 1.0)
  frame.text =~ "45%"
  #=> true
  ```

  ```heex
  <Ascii.Phoenix.live_player id="history" piece="sparkline" options={%{series: [%{label: "cpu", unit: "%", values: @cpu}]}} parts />
  ```

  Ported from `src/pieces/sparkline.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}
  alias Ascii.Kit.{Number, Text}

  @meta %Ascii.Meta{
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
    bounds: %{
      rate: {0, 100},
      cols: {40, 200},
      rows: {3, 32},
      series: %{values: {-1.0e15, 1.0e15}, lo: {-1.0e15, 1.0e15}, hi: {-1.0e15, 1.0e15}}
    },
    shapes: %{
      series: [%{label: "", unit: "", lo: 0.0, hi: 0.0, digits: 0, values: [0.0]}]
    },
    parts: [
      {"title", "#8b949e"},
      {"label", nil},
      {"spark", "#58a6ff"},
      {"spark.1", nil},
      {"spark.2", "#39c5cf"},
      {"spark.3", "#a371f7"},
      {"spark.4", "#db61a2"},
      {"spark.5", "#db6d28"},
      {"axis", "#8b949e"},
      {"value", nil},
      {"unit", nil},
      {"value.min", "#8b949e"},
      {"value.max", "#8b949e"},
      {"scale", "#8b949e"}
    ]
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

    value = s |> reading(List.last(win)) |> Text.pad_start(@vw)
    pad = String.duplicate(" ", w - length(win))
    line = IO.chardata_to_string(["  ", label(s), pad, bars, "▏ ", value])

    if range,
      do:
        line <>
          "  " <>
          Text.pad_start(figure(s, least), @rw) <>
          " " <> Text.pad_start(figure(s, most), @rw),
      else: line
  end

  defp label(s), do: (Map.get(s, :label) || "") |> Text.slice(0, @lw - 1) |> Text.pad_end(@lw)

  # JS's toFixed takes 0 to 100 digits and throws past them; here they are held to that range.
  defp fmt(s, v, unit?) do
    JSMath.to_fixed(v, digits(s)) <> if(unit?, do: Map.get(s, :unit) || "", else: "")
  end

  defp digits(s), do: (Map.get(s, :digits) || 0) |> trunc() |> max(0) |> min(100)

  # This port's own: a value too wide for its column, which upstream writes
  # past it, is written to fit (see Ascii.Kit.Number), its unit after it.
  defp reading(s, v) do
    plain = fmt(s, v, true)
    unit = Map.get(s, :unit) || ""
    room = @vw - Text.length(unit)

    if Text.length(plain) <= @vw or room < 1,
      do: plain,
      else: Number.fit(v, digits(s), room) <> unit
  end

  defp figure(s, v) do
    plain = fmt(s, v, false)
    if Text.length(plain) <= @rw, do: plain, else: Number.fit(v, digits(s), @rw)
  end

  # This port's own: in words, each series given values, its label and its
  # latest value written in full (but for a hundred decimals or a long unit).
  @impl true
  def describe(%{series: series}) do
    case for(s <- Enum.take(series, @slots), Map.has_key?(s, :values), do: told(s)) do
      [] -> nil
      told -> "sparkline: " <> Enum.join(told, ", ")
    end
  end

  defp told(s) do
    label = Text.slice(Map.get(s, :label) || "", 0, 24)

    value =
      case Map.get(s, :values) do
        [] ->
          "no samples"

        values ->
          JSMath.to_fixed(List.last(values), min(digits(s), 6)) <>
            Text.slice(Map.get(s, :unit) || "", 0, 12)
      end

    String.trim(label <> " " <> value)
  end

  # This port's own: the parts of a frame, read off its lines where init/1
  # lays them out: the headings, a row per series, then the time axis. A
  # series' row is its label, its line and the line's end at fixed columns,
  # then its value, unit and range, found in turn as fmt/3 wrote them.

  @word ~r/\S+/u
  @label ~r/\A( *)(.*?)( *)\z/u
  @spark ~r/\A( *)(.*)\z/u
  @number ~r/\A-?\d+(?:\.\d+)?(?:e[+-]\d+)?[kMGTPE]?/
  @unit ~r/\A( *)(.*)\z/su
  @range ~r/\A( *)(\S*)( *)(\S*)( *)\z/u

  @impl true
  def parts(%{lines: lines, cols: cols, rows: rows}, %{series: series, range: range}) do
    series = Enum.take(series, @slots)
    w = cols - 2 - @lw - 2 - @vw - if(range, do: 2 + @rw + 1 + @rw, else: 0) - 2
    {gap, span} = span(series)
    top = JSMath.floor((rows - span - 2) / 2) + 1
    at = series |> Enum.with_index() |> Map.new(fn {s, i} -> {top + i * gap, {s, i + 1}} end)

    for {line, y} <- Enum.with_index(lines) do
      case {Map.fetch(at, y), y - top} do
        {{:ok, s}, _} -> series_parts(line, s, w)
        {:error, -1} -> Parts.matches(line, @word, "title")
        {:error, ^span} -> Parts.matches(line, @word, "scale")
        {:error, _} -> Parts.line(line, nil)
      end
    end
  end

  defp series_parts(line, {s, n}, w) do
    {head, rest} = line |> String.to_charlist() |> Enum.split(2)
    {label, rest} = Enum.split(rest, @lw)
    {spark, rest} = Enum.split(rest, w)

    case rest do
      [?▏ | rest] ->
        {gap, rest} = Enum.split(rest, 1)

        Parts.merge(
          [{nil, List.to_string(head)}] ++
            Parts.captures(List.to_string(label), @label, [nil, "label", nil]) ++
            Parts.captures(List.to_string(spark), @spark, [nil, "spark.#{n}"]) ++
            [{"axis", "▏"}, {nil, List.to_string(gap)}] ++
            readings(List.to_string(rest), Map.get(s, :unit) || "")
        )

      _ ->
        Parts.line(line, nil)
    end
  end

  # The value, padded at the start, its unit after it, then the range. The
  # number is the longest the unit follows: a unit can start with a digit.
  defp readings(text, unit) do
    pad = byte_size(text) - byte_size(String.trim_leading(text, " "))
    <<lead::binary-size(^pad), rest::binary>> = text

    with [number] <- Regex.run(@number, rest),
         n when is_integer(n) <- Enum.find(byte_size(number)..1//-1, &unit_after?(rest, &1, unit)) do
      [{nil, lead}, {"value", binary_part(rest, 0, n)} | unit_parts(after_number(rest, n), unit)]
    else
      _ -> [{nil, text}]
    end
  end

  defp after_number(rest, n), do: binary_part(rest, n, byte_size(rest) - n)

  defp unit_after?(rest, n, unit) do
    text = after_number(rest, n)
    String.starts_with?(text, unit) or String.starts_with?(unit, text)
  end

  # The unit as given, or as much of it as the frame's edge leaves.
  defp unit_parts(text, unit) do
    cond do
      String.starts_with?(text, unit) ->
        n = byte_size(unit)

        Parts.captures(unit, @unit, [nil, "unit"]) ++
          range_parts(binary_part(text, n, byte_size(text) - n))

      String.starts_with?(unit, text) ->
        Parts.captures(text, @unit, [nil, "unit"])

      true ->
        [{nil, text}]
    end
  end

  defp range_parts(text),
    do: Parts.captures(text, @range, [nil, "value.min", nil, "value.max"]) || [{nil, text}]
end
