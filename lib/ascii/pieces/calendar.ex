defmodule Ascii.Pieces.Calendar do
  @moduledoc """
  This month like cal, today bracketed, time ticking below.

  This month laid out like the cal command, today in brackets, with the
  weekday and the running time along the bottom: upstream's calendar,
  which it is by default. Give it a `date` and it shows that month and day
  instead, and is a date picker that keys and clicks move.

  Reads the clock from `env.now` (see `Ascii.Kit.Clock`), for today and
  the running time.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): the page
  is drawn anew from them.

    * `date` - a day to show, as `"2026-10-12"`: its month, the day
      bracketed as the one selected, and along the bottom its weekday (and
      the time, if `time`). `"2026-10"` shows a month with nothing
      selected. Default `""`, as is any string that is not a date: this
      month, today bracketed, as upstream.
    * `marks` - days to mark, as `["2026-10-03", "2026-10-19"]`: those in
      the month shown wear a `·` after their number (a bracketed one, only
      where its cell has room). Default `[]`.
    * `monday` - weeks start on Monday rather than Sunday. Default `false`.
    * `time` - the running time at the right of the bottom line, from the
      clock, with a `date` too. Default `true`; `false` for a plain date
      picker.
    * `months`, `weekdays` - the names to use, twelve from January and
      seven from Sunday; the heading shows each weekday's first two
      letters. English by default; a list of another length is ignored.
    * `cols`, `rows` - the frame's size, 32 to 200 by 13 to 60; 32 by 13
      by default. The days' cells widen to fill the width, and the page
      sits in the middle.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `title` - the month and year.
    * `rule` - the rules above and below the weeks, grey.
    * `weekday` - the heading's days, grey; `weekday.weekend`, Saturday's
      and Sunday's, cyan.
    * `day` - a date; `day.weekend`, one on a weekend, cyan; and
      `day.marked`, one in `marks`, yellow.
    * `today` - today, bracketed, blue; or `selected`, the `date` given,
      blue.
    * `date`, `time` - the weekday and day, and the time, along the bottom.

  ## Keys and clicks

  With a `date`, it is a date picker: `Ascii.handle_event/2` takes keys
  and clicks, and the day chosen is the new `date`, from which the app
  reads it:

    * ← and → move the selection a day, ↑ and ↓ a week.
    * Page up and page down move it a month (to that month's last day, if
      it is shorter).
    * Home and end go to the month's first and last day.
    * A click on a day selects it.
    * From a month with nothing selected (`"2026-10"`), a key selects its
      first day (end, its last), and page up and page down change the
      month.

  Years stay within 1 to 9999. Without a `date`, the clock says which
  month it is, so there is none to move in: it takes none, and keys and
  clicks are ignored. In Phoenix, give the player `interactive` (and
  `notify` to be told of each key and click); in ExRatatui,
  `Ascii.ExRatatui.handle_event/3`; in a terminal,
  `mix ascii.play calendar --option date=2026-10-08 --option time=false --interactive`.

  ## Screen readers

  `Ascii.describe/1` tells the month shown, the day selected and the
  days marked in it, as "calendar: october 2026, 8 selected, marked 24",
  the month in the names given. Showing this month from the clock, it
  gives the piece's name and note.

  ## Example

  ```elixir
  options = %{date: "2026-10-08", time: false, marks: ["2026-10-24"]}
  picker = Ascii.new!("calendar", options: options, parts: true)
  Ascii.describe(picker)
  #=> "calendar: october 2026, 8 selected, marked 24"

  {:ok, picker} = Ascii.handle_event(picker, {:key, "right"})
  {:ok, picker} = Ascii.handle_event(picker, {:key, "page_down"})
  picker.options.date
  #=> "2026-11-09"

  # Upstream's: this month, at a given moment.
  now = DateTime.new!(~D[2026-03-14], ~T[15:09:26], "Etc/UTC")
  {frame, _} = Ascii.new!("calendar") |> Ascii.frame(0.0, now: now)
  frame.text =~ "[14]"
  #=> true
  ```

  ```heex
  <Ascii.Phoenix.live_player id="day" piece="calendar" options={%{date: @today, time: false, marks: @deadlines}} parts interactive notify />
  ```

  Ported from `src/pieces/calendar.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.{Clock, Text}
  alias Ascii.Parts

  @days ~w(sunday monday tuesday wednesday thursday friday saturday)
  @months ~w(january february march april may june july august september october november december)

  @meta %Ascii.Meta{
    name: "calendar",
    category: :ui,
    note: "this month like cal, today bracketed, time ticking below",
    cols: 32,
    rows: 13,
    fps: 8,
    options: %{
      monday: false,
      time: true,
      date: "",
      marks: [],
      months: @months,
      weekdays: @days,
      cols: 32,
      rows: 13
    },
    bounds: %{cols: {32, 200}, rows: {13, 60}},
    clock: true,
    parts: [
      {"title", nil},
      {"rule", "#8b949e"},
      {"weekday", "#8b949e"},
      {"weekday.weekend", "#39c5cf"},
      {"day", nil},
      {"day.weekend", "#39c5cf"},
      {"day.marked", "#d29922"},
      {"today", "#58a6ff"},
      {"selected", "#58a6ff"},
      {"date", nil},
      {"time", nil}
    ]
  }

  # The page's rows: a blank, the title, a rule, the weekdays, six weeks
  # and a rule; then the time line and a blank.
  @page 13
  @month ~r/^(\d{4})-(0[1-9]|1[0-2])$/

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{cols: cols, rows: rows}), do: {trunc(cols), trunc(rows)}

  @impl true
  def init(%{monday: monday, time: time} = options) do
    order = if monday, do: [1, 2, 3, 4, 5, 6, 0], else: [0, 1, 2, 3, 4, 5, 6]

    state = %{
      order: order,
      time: time,
      offset: nil,
      key: nil,
      page: [],
      layout: layout(options),
      months: names(options.months, @months),
      days: names(options.weekdays, @days),
      marks: marks(options.marks),
      shown: shown(options.date)
    }

    # A date given is a page that never changes.
    case state.shown do
      {:day, date} -> %{state | page: build(state, date.year, date.month, date.day)}
      {:month, y, m} -> %{state | page: build(state, y, m, nil)}
      :clock -> state
    end
  end

  # Where things go at this size: the frame, a day's cell, the margin, and
  # the page's first row.
  defp layout(options) do
    {cols, rows} = size(options)
    cell = div(cols - 4, 7)

    %{
      cols: cols,
      rows: rows,
      cell: cell,
      left: div(cols - 7 * cell, 2),
      top: div(rows - @page, 2)
    }
  end

  defp names(names, defaults) do
    if length(names) == length(defaults), do: List.to_tuple(names), else: List.to_tuple(defaults)
  end

  defp marks(dates) do
    for date <- dates, {:ok, d} <- [Date.from_iso8601(date)], into: MapSet.new(), do: d
  end

  # What the page shows: a day given, a month given, or the clock's.
  defp shown(date) do
    case {Date.from_iso8601(date), Regex.run(@month, date, capture: :all_but_first)} do
      {{:ok, d}, _} -> {:day, d}
      {_, [y, m]} -> {:month, String.to_integer(y), String.to_integer(m)}
      _ -> :clock
    end
  end

  defp pad(%{layout: %{cols: cols, left: left}}, s),
    do: (String.duplicate(" ", left) <> s) |> Text.pad_end(cols) |> Text.slice(0, cols)

  defp centre(%{layout: %{cell: cell}} = state, s),
    do: pad(state, String.duplicate(" ", max(0, floor((7 * cell - Text.length(s)) / 2))) <> s)

  # The month only changes at midnight, so the grid is built once a day.
  defp build(state, y, m, d) do
    %{cols: cols, cell: cell} = state.layout
    first = Date.new!(y, m, 1)
    lead = rem(Clock.weekday(first) - hd(state.order) + 7, 7)
    count = Date.days_in_month(first)

    weeks =
      for w <- 0..5 do
        pad(
          state,
          for(c <- 0..6, into: "", do: day_cell(state, w * 7 + c - lead + 1, d, {y, m, count}))
        )
      end

    rule = pad(state, String.duplicate("─", 7 * cell))
    heading = Enum.map_join(state.order, &slot(state, " " <> short(state, &1) <> " "))

    [
      String.duplicate(" ", cols),
      centre(state, elem(state.months, m - 1) <> " " <> Integer.to_string(y)),
      rule,
      pad(state, heading)
    ] ++ weeks ++ [rule]
  end

  # Day n of the month (or a blank cell), d the bracketed day.
  defp day_cell(state, n, d, {y, m, count}) do
    marked = n in 1..count//1 and MapSet.member?(state.marks, Date.new!(y, m, n))
    number = Text.pad_start(Integer.to_string(n), 2)

    cond do
      n < 1 or n > count -> slot(state, "    ")
      n == d and n < 10 -> slot(state, " [#{n}]", marked)
      n == d -> slot(state, "[#{n}]", marked)
      marked -> slot(state, " " <> number <> "·")
      true -> slot(state, " " <> number <> " ")
    end
  end

  defp short(state, day), do: state.days |> elem(day) |> Text.slice(0, 2) |> Text.pad_end(2)

  # Four cells in the middle of a cell of the layout's width; a marked day
  # in brackets has its mark just after, where there is room.
  defp slot(%{layout: %{cell: cell}}, s, marked \\ false) do
    left = div(cell - 4, 2)
    right = String.duplicate(" ", cell - 4 - left)
    right = if marked and right != "", do: "·" <> Text.slice(right, 1), else: right
    String.duplicate(" ", left) <> s <> right
  end

  @impl true
  def frame(%{time: time, layout: layout} = state, t, env) do
    # Play time ticks the clock so it steps evenly between frames; the wall
    # clock pulls it back whenever play was paused or fell behind.
    wall = Clock.now_ms(env) / 1000
    offset = state.offset

    offset =
      if offset == nil or wall - (offset + t) > 0.25 or offset + t - wall > 60,
        do: wall - t,
        else: offset

    now = Clock.local(env, trunc((offset + t) * 1000))
    {state, day} = page(state, now)

    clock = if time, do: Enum.map_join([now.hour, now.minute, now.second], ":", &two/1), else: ""
    foot = pad(state, " " <> day <> Text.pad_start(clock, 7 * layout.cell - 2 - Text.length(day)))
    blank = String.duplicate(" ", layout.cols)
    lines = List.duplicate(blank, layout.top) ++ state.page ++ [foot]
    lines = Enum.take(lines ++ List.duplicate(blank, layout.rows), layout.rows)

    {Enum.intersperse(lines, ?\n), nil, %{state | offset: offset}}
  end

  # The page, and the day along the bottom: today's, or the one given.
  defp page(%{shown: :clock} = state, now) do
    %{year: y, month: m, day: d} = now
    key = {y, m, d}
    page = if key == state.key, do: state.page, else: build(state, y, m, d)
    {%{state | key: key, page: page}, day_name(state, now)}
  end

  defp page(%{shown: {:day, date}} = state, _now), do: {state, day_name(state, date)}
  defp page(state, _now), do: {state, ""}

  defp day_name(state, date),
    do: elem(state.days, Clock.weekday(date)) <> " " <> Integer.to_string(date.day)

  defp two(n), do: n |> Integer.to_string() |> Text.pad_start(2, "0")

  # This port's own: the date picker. Every move is a new `date`, kept to
  # years of four digits.

  @impl true
  def handle_event({:key, key}, %{date: date} = options), do: key(shown(date), key, options)

  def handle_event({:click, x, y}, %{date: date} = options) do
    with {:ok, {year, month}} <- month_shown(shown(date)),
         {:ok, n} <- day_at(options, year, month, x, y) do
      select(options, Date.new!(year, month, n))
    else
      _ -> :ignore
    end
  end

  def handle_event(_event, _options), do: :ignore

  defp key({:day, d}, "left", o), do: select(o, Date.add(d, -1))
  defp key({:day, d}, "right", o), do: select(o, Date.add(d, 1))
  defp key({:day, d}, "up", o), do: select(o, Date.add(d, -7))
  defp key({:day, d}, "down", o), do: select(o, Date.add(d, 7))
  defp key({:day, d}, "page_up", o), do: select(o, Date.shift(d, month: -1))
  defp key({:day, d}, "page_down", o), do: select(o, Date.shift(d, month: 1))
  defp key({:day, d}, "home", o), do: select(o, Date.beginning_of_month(d))
  defp key({:day, d}, "end", o), do: select(o, Date.end_of_month(d))

  defp key({:month, y, m}, key, o) when key in ~w(left right up down home),
    do: select(o, Date.new!(y, m, 1))

  defp key({:month, y, m}, "end", o), do: select(o, Date.end_of_month(Date.new!(y, m, 1)))
  defp key({:month, y, m}, "page_up", o), do: month(o, Date.shift(Date.new!(y, m, 1), month: -1))
  defp key({:month, y, m}, "page_down", o), do: month(o, Date.shift(Date.new!(y, m, 1), month: 1))
  defp key(_shown, _key, _options), do: :ignore

  defp select(options, %Date{year: y} = d) when y in 1..9999,
    do: {:ok, %{options | date: Date.to_iso8601(d)}}

  defp select(_options, _date), do: :ignore

  defp month(options, %Date{year: y, month: m}) when y in 1..9999,
    do: {:ok, %{options | date: Integer.to_string(y) <> "-" <> two(m)}}

  defp month(_options, _date), do: :ignore

  defp month_shown({:day, d}), do: {:ok, {d.year, d.month}}
  defp month_shown({:month, y, m}), do: {:ok, {y, m}}
  defp month_shown(:clock), do: :error

  # The day in the cell at x, y, if there is one.
  defp day_at(options, year, month, x, y) do
    %{cell: cell, left: left, top: top} = layout(options)
    week = y - top - 4
    c = if x >= left, do: div(x - left, cell), else: -1
    first = Date.new!(year, month, 1)
    from = if options.monday, do: 1, else: 0
    n = week * 7 + c - rem(Clock.weekday(first) - from + 7, 7) + 1

    if week in 0..5 and c in 0..6 and n in 1..Date.days_in_month(first),
      do: {:ok, n},
      else: :error
  end

  # This port's own: words for a screen reader, with a date given.

  @impl true
  def describe(%{date: date, months: months, marks: marks}) do
    shown = shown(date)

    case month_shown(shown) do
      {:ok, {year, month}} ->
        name = months |> names(@months) |> elem(month - 1)
        "calendar: #{name} #{year}" <> selected(shown) <> marked(marks, year, month)

      :error ->
        nil
    end
  end

  defp selected({:day, d}), do: ", #{d.day} selected"
  defp selected(_shown), do: ""

  defp marked(marks, year, month) do
    days =
      for d <- marks(marks), d.year == year and d.month == month, do: d.day

    case Enum.sort(days) do
      [] -> ""
      days -> ", marked " <> list(Enum.map(days, &Integer.to_string/1))
    end
  end

  defp list([one]), do: one

  defp list(items) when length(items) > 8,
    do: Enum.join(Enum.take(items, 8), ", ") <> " and #{length(items) - 8} more"

  defp list(items), do: Enum.join(Enum.drop(items, -1), ", ") <> " and " <> List.last(items)

  # This port's own: the parts of a frame, by row of the page: the month, a
  # rule, the weekdays, six weeks and a rule, then the time line. The
  # weekdays and weeks are cells of the layout's width after its margin,
  # the weekend's columns known from the options.

  @title ~r/^( *)(.*?)( *)$/u
  @rule ~r/^( *)(─+)( *)$/u
  @cell ~r/^( *)(\S*)( *)$/u
  @foot ~r/^( *)(\S[^\d]*? \d+)?( *)(\d\d:\d\d:\d\d)?( *)$/u
  @weekend %{false: [0, 6], true: [5, 6]}

  @impl true
  def parts(%{lines: lines}, %{monday: monday, date: date} = options) do
    weekend = Map.fetch!(@weekend, monday == true)
    layout = layout(options)
    bracket = if shown(date) == :clock, do: "today", else: "selected"

    for {line, y} <- Enum.with_index(lines) do
      case y - layout.top do
        1 -> Parts.captures(line, @title, [nil, "title"])
        r when r in [2, 10] -> Parts.captures(line, @rule, [nil, "rule"])
        3 -> cells(line, layout, &weekday(&1, &2, weekend))
        r when r in 4..9 -> cells(line, layout, &day(&1, &2, weekend, bracket))
        11 -> Parts.captures(line, @foot, [nil, "date", nil, "time"])
        _ -> nil
      end || [{nil, line}]
    end
  end

  # A row of seven cells after the margin, each labelled by `name`.
  defp cells(line, %{cols: cols, cell: cell, left: left}, name) do
    chars = String.codepoints(line)

    if length(chars) == cols do
      {margin, rest} = Enum.split(chars, left)
      {grid, tail} = Enum.split(rest, 7 * cell)

      runs =
        grid
        |> Enum.chunk_every(cell)
        |> Enum.with_index()
        |> Enum.flat_map(fn {slot, c} ->
          slot = Enum.join(slot)
          Parts.captures(slot, @cell, [nil, name.(c, slot)]) || [{nil, slot}]
        end)

      Parts.merge([{nil, Enum.join(margin)} | runs] ++ [{nil, Enum.join(tail)}])
    end
  end

  defp weekday(c, _cell, weekend), do: if(c in weekend, do: "weekday.weekend", else: "weekday")

  defp day(c, cell, weekend, bracket) do
    cond do
      String.contains?(cell, "[") -> bracket
      String.contains?(cell, "·") -> "day.marked"
      c in weekend -> "day.weekend"
      true -> "day"
    end
  end
end
