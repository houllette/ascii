defmodule AsciiArt.Pieces.UptimeBar do
  @moduledoc """
  60-day uptime bars for three services, a new day slides in.

  A status page's 60-day uptime bars, one thin bar a day, for up to three
  services (more are cut). A degraded day is a short bar, a down day flat.

  ## Options

  `services` (upstream's) names them. This port adds, for a real status
  board:

    * `history` - for each service, its daily uptime in percent, oldest
      first, the last being today: a day of 99.95% or more is up, of 97% or
      more degraded, and less is an outage. Days before the first are left
      blank, and a service without a history plays upstream's.
    * `days` - how many days the bars span, 20 to 196; the frame is four
      columns wider, and labels that do not fit are cut.

  Ported from `src/pieces/uptime-bar.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Text

  @meta %AsciiArt.Meta{
    name: "uptime bar",
    category: :data,
    note: "60-day uptime bars for three services, a new day slides in",
    cols: 64,
    rows: 15,
    fps: 8,
    options: %{services: ["api", "website", "database"], history: [], days: 60},
    bounds: %{days: {20, 196}},
    shapes: %{history: [[0.0]]}
  }

  # Services shown; the frame has room for three.
  @max 3
  # Seconds per day; the end of each step, when the bars sit half a cell
  # along; today at t = 0, picked for a good opening 60 days.
  @step 1.25
  @slide 0.25
  @start 2646
  # Each state as a left-half bar, and as the same bar half a cell to the left.
  # A down day is flat on the floor.
  @bar {"▁", "▖", "▌"}
  @mid {"▁", "▗", "▐"}
  @rates {{0.03, 0.01}, {0.045, 0.014}, {0.025, 0.008}}
  @left 2

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{days: days}), do: {trunc(days) + 4, @meta.rows}

  @impl true
  def init(%{services: services, history: history} = options) do
    names = services |> Enum.take(@max) |> Enum.map(&Text.slice(&1, 0, 24))
    {cols, _rows} = size(options)
    w = cols - 4
    # The days on show of each history given, as {state, uptime} or nil.
    days =
      for s <- 0..(@max - 1) do
        case Enum.at(history, s) do
          h when is_list(h) and h != [] ->
            h = Enum.take(h, -w)
            List.duplicate(nil, w - length(h)) ++ Enum.map(h, &{state_of(&1), &1})

          _ ->
            nil
        end
      end

    # Fewer services sit in the middle of the frame.
    %{names: names, top: 1 + (@max - length(names)) * 2, days: days, w: w, cols: cols}
  end

  defp state_of(pct) when pct >= 99.95, do: 2
  defp state_of(pct) when pct >= 97, do: 1
  defp state_of(_pct), do: 0

  defp hash(s, d, k),
    do: (s * 7919 + d * 104_729 + k * 15_485_863) |> Int32.mulberry32() |> elem(0)

  # 2 up, 1 degraded, 0 down. An outage is often followed by a degraded day.
  defp base(s, d) do
    {deg, down} = elem(@rates, rem(s, tuple_size(@rates)))
    r = hash(s, d, 1)

    cond do
      r < down -> 0
      r < down + deg -> 1
      true -> 2
    end
  end

  defp state(s, d) do
    case base(s, d) do
      2 -> if base(s, d - 1) < 2 and hash(s, d, 2) < 0.5, do: 1, else: 2
      b -> b
    end
  end

  # Today's state: the history's last day, or upstream's.
  defp now(%{days: days}, s, today) do
    case Enum.at(days, s) do
      nil -> state(s, today)
      history -> history |> List.last() |> elem(0)
    end
  end

  # A service's bar and its uptime over the days shown. Upstream's slides
  # in a day at a time; a history given stands still.
  defp bar(%{w: w}, nil, s, today, half) do
    sum = Enum.reduce((today - w + 1)..today, 0, &(&2 + uptime(s, &1)))
    # Mid-slide, each cell holds the next day, drawn in its left neighbour's right half.
    {shift, glyphs} = if half, do: {1, @mid}, else: {0, @bar}
    bar = Enum.map_join(0..(w - 1), &elem(glyphs, state(s, today - w + 1 + &1 + shift)))
    {bar, sum / w}
  end

  defp bar(_st, days, _s, _today, _half) do
    known = Enum.reject(days, &is_nil/1)
    bar = Enum.map_join(days, fn day -> if day, do: elem(@bar, elem(day, 0)), else: " " end)
    {bar, Enum.sum(Enum.map(known, &elem(&1, 1))) / length(known)}
  end

  # Percent of the day the service was up.
  defp uptime(s, d) do
    case state(s, d) do
      2 -> 100
      1 -> 99.9 - hash(s, d, 3) * 0.6
      0 -> 96 - hash(s, d, 4) * 9
    end
  end

  defp pad(st, l, r \\ "") do
    gap = max(1, st.w - Text.length(l) - Text.length(r))
    Text.pad_end(String.duplicate(" ", @left) <> l <> String.duplicate(" ", gap) <> r, st.cols)
  end

  # "60 days ago ···· 99.92% uptime ···· today", dotted to the bar's width.
  defp footer(st, pct) do
    a = "#{st.w} days ago "
    b = " today"
    mid = " " <> JSMath.to_fixed(pct, 2) <> "% uptime "
    gap = st.w - Text.length(a) - Text.length(b) - Text.length(mid)
    l = Int32.sar(gap, 1)
    pad(st, a <> Text.repeat("·", l) <> mid <> Text.repeat("·", gap - l) <> b)
  end

  @impl true
  def frame(%{names: names, top: top, cols: cols} = st, t, _env) do
    %{rows: rows} = @meta
    p = (t + 0.5) / @step
    today = @start + JSMath.floor(p)
    half = p - JSMath.floor(p) > 1 - @slide / @step
    count = length(names)
    now = for s <- 0..(count - 1)//1, do: now(st, s, today)
    worst = Enum.min([2 | now])

    status =
      case worst do
        2 -> "all systems operational"
        1 -> "degraded performance"
        0 -> "partial outage"
      end

    services =
      names
      |> Enum.zip(now)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{name, state}, s} ->
        word = elem({"outage", "degraded", "operational"}, state)
        {bar, pct} = bar(st, Enum.at(st.days, s), s, today, half)
        [pad(st, name, word), pad(st, bar), footer(st, pct), ""]
      end)

    lines = List.duplicate("", top) ++ [pad(st, status), ""] ++ services
    lines = lines ++ List.duplicate("", max(rows - length(lines), 0))

    lines =
      lines
      |> Enum.take(rows)
      |> Enum.map(&(&1 |> Text.slice(0, cols) |> Text.pad_end(cols)))

    {Enum.intersperse(lines, ?\n), nil, st}
  end
end
