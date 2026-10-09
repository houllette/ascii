defmodule Ascii.Pieces.Heatmap do
  @moduledoc """
  Contribution calendar, a day at a time, weeks scrolling left.

  A contribution calendar, weeks across and weekdays down, shaded by how busy
  each day was. As upstream draws it, days fill in one at a time and a full
  week moves it left; give it `counts` and it shows your activity instead,
  standing still.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): the
  calendar is drawn anew from them, a day's new count as soon as it comes.

    * `counts` - each day's count, oldest first, the last being `date`, up
      to a billion either way. Days are shaded in four steps of the busiest
      day's count, as GitHub does; days before the first are blank. Default
      `[]`: upstream's made-up activity, filling in a day at a time.
    * `date` - the last count's day, as `"2026-10-07"`. Default `""`: today,
      from the clock (or `now:`, see `Ascii.frame/3`).
    * `weeks` - how many weeks show, 12 to 97; the frame is two columns a
      week and six more wide, and always 12 rows tall. Default 30.
    * `unit` - what is counted, after the total under the calendar. Default
      `"contributions"`.
    * `months`, `weekdays` - the names to use, twelve from January and
      seven from Sunday, of which the scale shows the first three letters
      (months along the top, Monday, Wednesday and Friday down the side).
      English by default; a list of another length is ignored.
    * `seed` - the seed of upstream's made-up activity. Default 7.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here, GitHub's greens:

    * `scale` - the months and weekdays, grey.
    * `level.0` - an empty day, grey.
    * `level.1`, `level.2`, `level.3`, `level.4` - the days by their shade,
      quietest to busiest: dark green, green, bright green and brightest
      green.
    * `value`, `unit` - the total under the calendar, and its unit.
    * `legend` - the key's words, grey; its shades are in their levels.

  ## Keys and clicks

  It takes none: it shows activity, and `Ascii.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still tells
  your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): a day's `level.3`, say.

  ## Screen readers

  `Ascii.describe/1` reads the counts given, their total, unit and span,
  and the busiest day's count: "heatmap: 19 commits in the last 12 weeks,
  busiest day 9". With a `date`, the total is the frame's own; without one
  it takes the last `weeks` of counts. Without counts, it gives the
  piece's name and note.

  ## Example

  ```elixir
  options = %{counts: [0, 1, 2, 4, 9, 3], date: "2026-10-07", unit: "commits", weeks: 12}
  map = Ascii.new!("heatmap", options: options, parts: true)

  {frame, _map} = Ascii.frame(map, 0.0)
  {frame.cols, frame.rows}
  #=> {30, 12}

  Ascii.describe(map)
  #=> "heatmap: 19 commits in the last 12 weeks, busiest day 9"
  ```

  ```heex
  <Ascii.Phoenix.live_player id="commits" piece="heatmap" options={%{counts: @counts, unit: "commits"}} parts />
  ```

  Ported from `src/pieces/heatmap.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}
  alias Ascii.Kit.Text

  @month_names ~w(january february march april may june july august september october november december)
  @day_names ~w(sunday monday tuesday wednesday thursday friday saturday)

  @meta %Ascii.Meta{
    name: "heatmap",
    category: :data,
    note: "contribution calendar, a day at a time, weeks scrolling left",
    cols: 66,
    rows: 12,
    fps: 10,
    options: %{
      unit: "contributions",
      seed: 7,
      counts: [],
      date: "",
      weeks: 30,
      months: @month_names,
      weekdays: @day_names
    },
    bounds: %{weeks: {12, 97}, counts: {-1.0e9, 1.0e9}},
    shapes: %{counts: [0.0]},
    parts: [
      {"scale", "#8b949e"},
      {"level.0", "#8b949e"},
      {"level.1", "#006d32"},
      {"level.2", "#26a641"},
      {"level.3", "#3fb950"},
      {"level.4", "#39d353"},
      {"value", nil},
      {"unit", nil},
      {"legend", "#8b949e"}
    ]
  }

  # Seconds per day; today at t = 0, as days since 1970-01-01.
  @step 0.5
  @start 20_150
  @levels {"·", "░", "▒", "▓", "█"}
  # Weekday labels: Monday, Wednesday and Friday, of the rows from Monday.
  @labelled [0, 2, 4]
  @left 6

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{weeks: weeks}), do: {@left + 2 * trunc(weeks), @meta.rows}

  @impl true
  def init(%{unit: unit, seed: seed, counts: counts, date: date} = options) do
    days = names(options.weekdays, @day_names)

    labels =
      for r <- 0..6 do
        name = if r in @labelled, do: Text.slice(elem(days, rem(r + 1, 7)), 0, 3), else: ""
        Text.pad_end(name, @left - 2) <> "  "
      end

    months =
      for name <- Tuple.to_list(names(options.months, @month_names)), do: Text.slice(name, 0, 3)

    key = "less " <> Enum.join(Tuple.to_list(@levels), " ") <> " more"
    {cols, _rows} = size(options)

    given =
      if counts != [] do
        busiest = Enum.max(counts)
        %{counts: List.to_tuple(counts), busiest: busiest, date: day_of(date)}
      end

    %{
      unit: unit,
      seed: seed,
      labels: labels,
      key: key,
      cols: cols,
      weeks: trunc(options.weeks),
      months: List.to_tuple(months),
      given: given
    }
  end

  defp names(names, defaults) do
    if length(names) == length(defaults), do: List.to_tuple(names), else: List.to_tuple(defaults)
  end

  # Days since 1970-01-01, or nil to read today's when drawing.
  defp day_of(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> Date.diff(d, ~D[1970-01-01])
      _ -> nil
    end
  end

  # Month (0 to 11) of a day counted from 1970-01-01, after Howard Hinnant.
  defp month_of(z) do
    doe = Integer.mod(z + 719_468, 146_097)
    yoe = div(doe - div(doe, 1460) + div(doe, 36_524) - div(doe, 146_096), 365)
    doy = doe - (365 * yoe + div(yoe, 4) - div(yoe, 100))
    mp = div(5 * doy + 2, 153)
    rem(mp + 2, 12)
  end

  defp hash(seed, d, k),
    do: (seed * 7919 + d * 104_729 + k * 15_485_863) |> Int32.mulberry32() |> elem(0)

  # Busy and quiet stretches: value noise over weeks, eased between knots.
  defp busy(seed, d) do
    w = d / 7 / 3
    i = JSMath.floor(w)
    f = w - i
    e = f * f * (3 - 2 * f)
    hash(seed, i, 9) * (1 - e) + hash(seed, i + 1, 9) * e
  end

  # Today as days since 1970-01-01: upstream's, stepping on with play time,
  # or the day of the last count given, which stands still.
  defp today(nil, t, _env), do: @start + JSMath.floor(t / @step)
  defp today(%{date: day}, _t, _env) when is_integer(day), do: day

  defp today(_given, _t, env) do
    date = if env.now, do: DateTime.to_date(env.now), else: Date.utc_today()
    Date.diff(date, ~D[1970-01-01])
  end

  # A day's count: upstream's, or the one given, or nil before the first.
  defp count(nil, seed, _today, d), do: count(seed, d)

  defp count(%{counts: counts}, _seed, today, d) do
    i = tuple_size(counts) - 1 - (today - d)
    if i >= 0, do: elem(counts, i)
  end

  # Upstream's steps, or four steps of the busiest day.
  defp level(nil, n), do: level(n)
  defp level(_given, n) when n <= 0, do: 0
  defp level(%{busiest: busiest}, n), do: min(4, JSMath.ceil(n / busiest * 4))

  defp count(seed, d) do
    weekend = rem(d + 3, 7) >= 5
    a = (0.08 + 1.05 * :math.pow(busy(seed, d), 1.4)) * if(weekend, do: 0.3, else: 1)

    if hash(seed, d, 1) > a + 0.08,
      do: 0,
      else: max(1, JSMath.round(a * (3 + 14 * hash(seed, d, 2))))
  end

  defp level(0), do: 0
  defp level(n) when n < 4, do: 1
  defp level(n) when n < 8, do: 2
  defp level(n) when n < 12, do: 3
  defp level(_n), do: 4

  @impl true
  def frame(%{seed: seed, cols: cols, weeks: weeks, given: given} = state, t, env) do
    today = today(given, t, env)
    monday = today - rem(today + 3, 7)
    first = monday - (weeks - 1) * 7

    # Day by day, row by row: each cell and the running total.
    {cells, total} =
      Enum.map_reduce(0..6, 0, fn r, total ->
        Enum.map_reduce(0..(weeks - 1), total, fn w, total ->
          d = first + w * 7 + r

          case d <= today and count(given, seed, today, d) do
            n when is_number(n) -> {[elem(@levels, level(given, n)), ?\s], total + n}
            _ -> {"  ", total}
          end
        end)
      end)

    # Upstream adds the counts week by week; a sum of integers is the same in any order.
    rows = Enum.zip_with(state.labels, cells, &[&1 | &2])

    sum =
      group(JSMath.to_string(total)) <> " " <> state.unit <> " in the last #{weeks} weeks"

    # The key, where there is room for it beside the total.
    room = cols - @left - Text.length(state.key) - 1

    foot =
      if Text.length(sum) <= room,
        do: String.duplicate(" ", @left) <> Text.pad_end(sum, room) <> state.key,
        else: String.duplicate(" ", @left) <> sum

    lines =
      ["", head(first, cols, weeks, state.months)] ++
        Enum.map(rows, &IO.chardata_to_string/1) ++ ["", foot, ""]

    lines = Enum.map(lines, &(&1 |> Text.slice(0, cols) |> Text.pad_end(cols)))
    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # A month's name sits over the first week that starts in it.
  defp head(first, cols, weeks, months) do
    {cells, _} =
      Enum.reduce(0..(weeks - 1), {%{}, 0}, fn w, {cells, free} ->
        m = month_of(first + w * 7)
        x = @left + w * 2

        cond do
          w > 0 and m == month_of(first + (w - 1) * 7) -> {cells, free}
          x < free or x + 3 > cols -> {cells, free}
          w == 0 and month_of(first + 14) != m -> {cells, free}
          true -> {put_name(cells, x, elem(months, m)), x + 5}
        end
      end)

    Enum.map_join(0..(cols - 1), &Map.get(cells, &1, " "))
  end

  defp put_name(cells, x, name) do
    name |> Text.chars() |> Enum.with_index(x) |> Enum.into(cells, fn {ch, c} -> {c, ch} end)
  end

  # This port's own: words for a screen reader, with counts given: the
  # total and the busiest day of those shown. Without a date, the days
  # shown end today, which only the frame knows: here they are the last
  # `weeks` whole weeks of counts.

  @impl true
  def describe(%{counts: []}), do: nil

  def describe(%{counts: counts, unit: unit, date: date, weeks: weeks}) do
    weeks = trunc(weeks)

    shown =
      case day_of(date) do
        nil -> weeks * 7
        today -> rem(today + 3, 7) + 1 + (weeks - 1) * 7
      end

    days = Enum.take(counts, -shown)
    total = group(JSMath.to_string(Enum.sum(days)))
    what = if unit == "", do: total, else: total <> " " <> unit

    "heatmap: #{what} in the last #{weeks} weeks, busiest day " <>
      JSMath.to_string(Enum.max(days))
  end

  # Thousands separated by commas, as upstream's regex does it.
  defp group(digits), do: Regex.replace(~r/\B(?=(\d{3})+$)/, digits, ",")

  # This port's own: the parts of a frame, read off its rows, which sit
  # where frame/3 puts them: the months, a row of days for each weekday, and
  # the total, with the key at the end if there was room for it.

  @level_of for {glyph, i} <- @levels |> Tuple.to_list() |> Enum.with_index(),
                into: %{},
                do: {glyph, "level.#{i}"}

  # The key as init/1 makes it, and its runs, with the space after it.
  @key "less " <> Enum.join(Tuple.to_list(@levels), " ") <> " more"
  @legend @key
          |> String.split(" ")
          |> Enum.map(&{Map.get(@level_of, &1, "legend"), &1})
          |> Enum.intersperse({nil, " "})
          |> Kernel.++([{nil, " "}])

  @word ~r/\S+/u

  @impl true
  def parts(%{lines: lines}, %{unit: unit}) do
    for {line, y} <- Enum.with_index(lines) do
      cond do
        y == 1 -> Parts.matches(line, @word, "scale")
        y in 2..8 -> week_row(line)
        y == 10 -> foot(line, unit)
        true -> Parts.line(line, nil)
      end
    end
  end

  # A weekday's name, whatever its letters, then its days.
  defp week_row(line) do
    label = Text.slice(line, 0, @left)

    Parts.merge(
      Parts.matches(label, @word, "scale") ++ Parts.chars(Text.slice(line, @left), &day/1)
    )
  end

  defp day(" "), do: nil
  defp day(glyph), do: Map.get(@level_of, glyph, "scale")

  # The total, its unit and the rest of the sentence, maybe cut; then the key.
  defp foot(line, unit) do
    if String.ends_with?(line, " " <> @key <> " ") do
      sum = binary_part(line, 0, byte_size(line) - byte_size(@key) - 1)
      total(sum, unit) ++ @legend
    else
      total(line, unit)
    end
  end

  defp total(<<margin::binary-size(@left), sum::binary>>, unit) do
    {count, gap, rest} =
      case :binary.split(sum, " ") do
        [count, rest] -> {count, " ", rest}
        [count] -> {count, "", ""}
      end

    # As much of the unit as shows.
    n = min(Text.length(unit), Text.length(rest))
    shown = Text.slice(rest, 0, n)
    named = if shown == Text.slice(unit, 0, n), do: "unit"

    Parts.merge([
      {nil, margin},
      {"value", count},
      {nil, gap},
      {named, shown},
      {nil, Text.slice(rest, n)}
    ])
  end

  defp total(line, _unit), do: Parts.line(line, nil)
end
