defmodule AsciiArt.Pieces.Heatmap do
  @moduledoc """
  Contribution calendar, a day at a time, weeks scrolling left.

  A contribution calendar, weeks across and weekdays down, shaded by how busy
  each day was. Days fill in one at a time; a full week moves it left.

  ## Options

  `unit` and `seed` are upstream's. This port adds, for real activity:

    * `counts` - each day's count, oldest first, the last being `date`. Days
      are shaded in four steps of the busiest day's count, as GitHub does,
      and the calendar stands still. Days before the first are blank.
    * `date` - the last count's day, as `"2026-10-07"`; today by default.
    * `weeks` - how many weeks show, 12 to 97; the frame is two columns a
      week and six more.

  Ported from `src/pieces/heatmap.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Text

  @meta %AsciiArt.Meta{
    name: "heatmap",
    category: :data,
    note: "contribution calendar, a day at a time, weeks scrolling left",
    cols: 66,
    rows: 12,
    fps: 10,
    options: %{unit: "contributions", seed: 7, counts: [], date: "", weeks: 30},
    bounds: %{weeks: {12, 97}},
    shapes: %{counts: [0.0]}
  }

  # Seconds per day; today at t = 0, as days since 1970-01-01.
  @step 0.5
  @start 20_150
  @levels {"·", "░", "▒", "▓", "█"}
  @months {"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"}
  @days ["mon", "", "wed", "", "fri", "", ""]
  # Weekday labels.
  @left 6

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{weeks: weeks}), do: {@left + 2 * trunc(weeks), @meta.rows}

  @impl true
  def init(%{unit: unit, seed: seed, counts: counts, date: date} = options) do
    labels = Enum.map(@days, &(Text.pad_end(&1, @left - 2) <> "  "))
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
      given: given
    }
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
      ["", head(first, cols, weeks)] ++ Enum.map(rows, &IO.chardata_to_string/1) ++ ["", foot, ""]

    lines = Enum.map(lines, &(&1 |> Text.slice(0, cols) |> Text.pad_end(cols)))
    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # A month's name sits over the first week that starts in it.
  defp head(first, cols, weeks) do
    {cells, _} =
      Enum.reduce(0..(weeks - 1), {%{}, 0}, fn w, {cells, free} ->
        m = month_of(first + w * 7)
        x = @left + w * 2

        cond do
          w > 0 and m == month_of(first + (w - 1) * 7) -> {cells, free}
          x < free or x + 3 > cols -> {cells, free}
          w == 0 and month_of(first + 14) != m -> {cells, free}
          true -> {put_name(cells, x, elem(@months, m)), x + 5}
        end
      end)

    Enum.map_join(0..(cols - 1), &Map.get(cells, &1, " "))
  end

  defp put_name(cells, x, name) do
    name |> Text.chars() |> Enum.with_index(x) |> Enum.into(cells, fn {ch, c} -> {c, ch} end)
  end

  # Thousands separated by commas, as upstream's regex does it.
  defp group(digits), do: Regex.replace(~r/\B(?=(\d{3})+$)/, digits, ",")
end
