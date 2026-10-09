defmodule Ascii.Pieces.DigitalClock do
  @moduledoc """
  The local time in seven-segment digits, colon blinking.

  The local time as big seven-segment digits, HH:MM:SS, with the colon
  blinking each second and the date set small underneath, as upstream
  draws it. Give it a `timer` and it is a countdown or a stopwatch
  instead, which keeps play time rather than the clock.

  Reads the clock from `env.now` (see `Ascii.Kit.Clock`), as a clock.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): a timer
  runs on through a new `label` or look, and starts again from `from` when
  `timer` or `from` change.

    * `timer` - `"down"` counts down from `from` to zero, where the digits
      flash; `"up"` counts up from `from`, as a stopwatch, to 99:59:59.
      Both start with play. Default `""`, as is any other string: the
      clock.
    * `from` - the seconds a timer starts at, 0 to 359,999 (99:59:59).
      Default `0`.
    * `label` - a line beneath a timer, where the clock has its date.
      Default `""`.
    * `seconds` - the seconds' pair of digits; `false` shows hours and
      minutes alone. Default `true`.
    * `hour12` - a 12-hour clock: its first digit dark rather than a zero,
      and `am` or `pm` after the date. Default `false`.
    * `date` - the clock's date beneath the digits, as "saturday 14 march
      2026"; without it the digits sit a row lower. Default `true`.

  A timer shows hours, minutes and seconds (with `seconds: false`, hours
  and minutes), its colons blinking while it runs. The frame is always 70
  by 11.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `digit.on` - the digits' lit segments; `digit.off`, the unlit ones,
      faintly showing like the glass of a real display, grey.
    * `colon.on` - the colons lit; `colon.off`, dark as they blink, grey.
    * `date` - the clock's date beneath the digits; `label`, a timer's
      line.
    * `ampm` - a 12-hour clock's `am` or `pm`, cyan.

  ## Keys and clicks

  It takes none: it tells the time, and `Ascii.handle_event/2` ignores
  every event; start a timer again with a new `from`
  (`Ascii.put_options/2`). A Phoenix player given `interactive` and
  `notify` still tells your LiveView where it was clicked, and on which
  part (`Ascii.part_at/4`).

  ## Screen readers

  `Ascii.describe/1` tells a timer, with its label, as "tea: countdown
  from 5:00" or "stopwatch"; not the time left, which changes every
  second. As a clock, it gives the piece's name and note.

  ## Example

  ```elixir
  tea = Ascii.new!("digital-clock", options: %{timer: "down", from: 300, label: "tea"}, parts: true)
  Ascii.describe(tea)
  #=> "tea: countdown from 5:00"

  # A minute in, four minutes to go, with its label beneath.
  {frame, _tea} = Ascii.frame(tea, 60.0)
  frame.text =~ "tea"
  #=> true

  # The clock, at a given moment.
  now = DateTime.new!(~D[2026-03-14], ~T[15:09:26], "Etc/UTC")
  clock = Ascii.new!("digital-clock", options: %{hour12: true})
  {frame, _clock} = Ascii.frame(clock, 0.0, now: now)
  frame.text =~ "saturday 14 march 2026  pm"
  #=> true
  ```

  ```heex
  <Ascii.Phoenix.live_player id="tea" piece="digital-clock" options={%{timer: "down", from: 300, label: "tea"}} parts />
  ```

  Ported from `src/pieces/digital-clock.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.{Clock, Grid, Text}
  alias Ascii.Parts
  import Bitwise

  @meta %Ascii.Meta{
    name: "digital clock",
    category: :ui,
    note: "the local time in seven-segment digits, colon blinking",
    cols: 70,
    rows: 11,
    fps: 10,
    options: %{hour12: false, seconds: true, date: true, timer: "", from: 0, label: ""},
    bounds: %{from: {0, 359_999}},
    clock: true,
    parts: [
      {"digit.on", nil},
      {"digit.off", "#8b949e"},
      {"colon.on", nil},
      {"colon.off", "#8b949e"},
      {"date", nil},
      {"label", nil},
      {"ampm", "#39c5cf"}
    ]
  }

  # A digit is 8 cells wide and 7 tall, about 4:7 once cells are drawn twice as
  # tall as wide. Segments a to g as {row0, row1, col0, col1}.
  @dw 8
  @dh 7
  @segs [
    {0, 0, 2, @dw - 3},
    {1, 2, @dw - 2, @dw - 1},
    {4, 5, @dw - 2, @dw - 1},
    {6, 6, 2, @dw - 3},
    {4, 5, 0, 1},
    {1, 2, 0, 1},
    {3, 3, 2, @dw - 3}
  ]
  @digits {0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F}
  @days {"sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"}
  @months {"january", "february", "march", "april", "may", "june", "july", "august", "september",
           "october", "november", "december"}

  @impl true
  def meta, do: @meta

  # A timer's last second: 99:59:59.
  @most 359_999

  @impl true
  def init(%{hour12: hour12, seconds: seconds, date: date} = options) do
    timer = timer(options)
    line? = if timer, do: options.label != "", else: date

    %{
      hour12: hour12,
      seconds: seconds,
      date: date,
      top: if(line?, do: 1, else: 2),
      offset: nil,
      timer: timer,
      label: options.label,
      # When the timer started, in play time: the first frame's.
      since: 0.0
    }
  end

  # A timer counting `:down` or `:up` from its whole seconds, or nil for
  # the clock.
  defp timer(%{timer: "down", from: from}), do: {:down, trunc(from)}
  defp timer(%{timer: "up", from: from}), do: {:up, trunc(from)}
  defp timer(_options), do: nil

  # A new label carries on; a new timer, or a new start, starts afresh.
  @impl true
  def update(state, options) do
    fresh = init(options)

    if fresh.timer == state.timer,
      do: %{fresh | since: state.since, offset: state.offset},
      else: %{fresh | since: nil, offset: state.offset}
  end

  # Unlit segments stay faintly visible, like the glass of a real display.
  defp digit(grid, top, x, n) do
    mask = if n < 0, do: 0, else: elem(@digits, n)

    @segs
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {{r0, r1, c0, c1}, s}, grid ->
      ch = if band(bsr(mask, s), 1) == 1, do: "█", else: "░"
      for r <- r0..r1, c <- c0..c1, reduce: grid, do: (grid -> Grid.put(grid, x + c, top + r, ch))
    end)
  end

  defp colon(grid, top, x, on) do
    ch = if on, do: "█", else: "░"
    for r <- [2, 4], c <- [x, x + 1], reduce: grid, do: (grid -> Grid.put(grid, c, top + r, ch))
  end

  @impl true
  def frame(%{timer: {_way, _from}} = state, t, _env) do
    since = state.since || t
    {pairs, on} = running(state.timer, max(0.0, t - since), state.seconds)
    grid = digits(state, pairs, on, false)
    grid = if state.label != "", do: centred(grid, state.top + @dh + 1, state.label), else: grid
    {Grid.to_iodata(grid), nil, %{state | since: since}}
  end

  def frame(%{hour12: hour12, top: top} = state, t, env) do
    # Play time ticks the clock so it steps evenly between frames; the wall
    # clock pulls it back whenever play was paused or fell behind.
    wall = Clock.now_ms(env) / 1000
    offset = state.offset

    offset =
      if offset == nil or wall - (offset + t) > 0.25 or offset + t - wall > 60,
        do: wall - t,
        else: offset

    secs = offset + t
    now = Clock.local(env, trunc(secs * 1000))
    on = secs - floor(secs) < 0.5

    h = now.hour
    pm = h >= 12
    h = if hour12, do: if(rem(h, 12) == 0, do: 12, else: rem(h, 12)), else: h
    pairs = Enum.take([h, now.minute, now.second], if(state.seconds, do: 3, else: 2))
    grid = digits(state, pairs, on, hour12)
    grid = if state.date, do: date_line(grid, top, now, hour12, pm), else: grid
    {Grid.to_iodata(grid), nil, %{state | offset: offset}}
  end

  # The pairs of digits, centred, colons between them. A pair of -1s is
  # dark: a timer at zero, flashing.
  defp digits(%{top: top}, pairs, on, hour12) do
    %{cols: cols, rows: rows} = @meta
    n = length(pairs)
    width = n * (2 * @dw + 2) + (n - 1) * 6
    x = floor((cols - width) / 2)

    {grid, _} =
      pairs
      |> Enum.with_index()
      |> Enum.reduce({Grid.new(cols, rows), x}, fn {v, i}, {grid, x} ->
        {grid, x} = if i > 0, do: {colon(grid, top, x + 2, on), x + 6}, else: {grid, x}
        # A 12-hour clock leaves its first digit dark rather than showing a zero.
        tens = if (i == 0 and hour12 and v < 10) or v < 0, do: -1, else: div(v, 10)

        grid =
          grid
          |> digit(top, x, tens)
          |> digit(top, x + @dw + 2, if(v < 0, do: -1, else: rem(v, 10)))

        {grid, x + 2 * @dw + 2}
      end)

    grid
  end

  # A timer `elapsed` seconds in: its pairs of digits, and whether its
  # colons are lit. Counting down, the time left is shown whole seconds
  # up, so it starts on `from` and reaches zero as time runs out; there it
  # flashes, colons lit.
  defp running({:down, from}, elapsed, seconds?) do
    left = from - elapsed

    if left <= 0 do
      flash = elapsed - from - floor(elapsed - from) < 0.5

      {if(flash, do: pairs(0, seconds?), else: Enum.map(pairs(0, seconds?), fn _ -> -1 end)),
       true}
    else
      {pairs(min(ceil(left), @most), seconds?), elapsed - floor(elapsed) < 0.5}
    end
  end

  defp running({:up, from}, elapsed, seconds?) do
    shown = min(from + floor(elapsed), @most)
    {pairs(shown, seconds?), shown == @most or elapsed - floor(elapsed) < 0.5}
  end

  defp pairs(s, seconds?) do
    Enum.take([div(s, 3600), div(rem(s, 3600), 60), rem(s, 60)], if(seconds?, do: 3, else: 2))
  end

  defp centred(grid, r, s) do
    s = Text.slice(s, 0, @meta.cols)
    Grid.put_string(grid, floor((@meta.cols - Text.length(s)) / 2), r, s)
  end

  defp date_line(grid, top, now, hour12, pm) do
    line =
      elem(@days, Clock.weekday(now)) <>
        " #{now.day} " <> elem(@months, now.month - 1) <> " #{now.year}"

    line = if hour12, do: line <> if(pm, do: "  pm", else: "  am"), else: line
    c0 = floor((@meta.cols - Text.length(line)) / 2)
    Grid.put_string(grid, c0, top + @dh + 1, line)
  end

  # This port's own: words for a screen reader, for a timer.

  @impl true
  def describe(options) do
    case timer(options) do
      nil -> nil
      {:down, from} -> label(options) <> "countdown from " <> duration(from)
      {:up, 0} -> label(options) <> "stopwatch"
      {:up, from} -> label(options) <> "stopwatch from " <> duration(from)
    end
  end

  defp label(%{label: ""}), do: ""
  defp label(%{label: label}), do: label <> ": "

  defp duration(s) when s >= 3600,
    do: "#{div(s, 3600)}:#{two(div(rem(s, 3600), 60))}:#{two(rem(s, 60))}"

  defp duration(s), do: "#{div(s, 60)}:#{two(rem(s, 60))}"

  defp two(n), do: n |> Integer.to_string() |> Text.pad_start(2, "0")

  # This port's own: the parts of a frame. The digits and colons sit where
  # the options put them, lit in `█` and unlit in `░`, the colons in columns
  # of their own; the date is the line beneath, a 12-hour clock's half at
  # its end.

  @date ~r/^( *)(\S.*?)( *)$/
  @date12 ~r/^( *)(\S.*?)(  )(am|pm)( *)$/

  @impl true
  def parts(%{lines: lines}, %{hour12: hour12, seconds: seconds} = options) do
    {line?, under} =
      if timer(options),
        do: {options.label != "", &label_parts/1},
        else: {options.date, &date_parts(&1, hour12)}

    top = if line?, do: 1, else: 2
    colons = colons(if(seconds, do: 3, else: 2))

    for {line, y} <- Enum.with_index(lines) do
      cond do
        y >= top and y < top + @dh -> segments(line, colons)
        line? and y == top + @dh + 1 -> under.(line)
        true -> Parts.line(line, nil)
      end
    end
  end

  # The columns of the colons between n pairs of digits, laid out as frame/3 lays them.
  defp colons(n) do
    x = Integer.floor_div(@meta.cols - (n * (2 * @dw + 2) + (n - 1) * 6), 2)
    for i <- 1..(n - 1)//1, c <- [2, 3], do: x + i * (2 * @dw + 2) + (i - 1) * 6 + c
  end

  defp segments(line, colons) do
    line
    |> String.codepoints()
    |> Enum.with_index()
    |> Enum.map(fn {ch, x} -> {segment(ch, x in colons), ch} end)
    |> Parts.merge()
  end

  defp segment("█", true), do: "colon.on"
  defp segment("░", true), do: "colon.off"
  defp segment("█", false), do: "digit.on"
  defp segment("░", false), do: "digit.off"
  defp segment(_blank, _colon?), do: nil

  defp date_parts(line, true),
    do: Parts.captures(line, @date12, [nil, "date", nil, "ampm", nil]) || date_parts(line, false)

  defp date_parts(line, false),
    do: Parts.captures(line, @date, [nil, "date", nil]) || Parts.line(line, nil)

  defp label_parts(line),
    do: Parts.captures(line, @date, [nil, "label", nil]) || Parts.line(line, nil)
end
