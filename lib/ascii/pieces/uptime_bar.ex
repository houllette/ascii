defmodule Ascii.Pieces.UptimeBar do
  @moduledoc """
  60-day uptime bars for three services, a new day slides in.

  A status page's 60-day uptime bars, one thin bar a day, for up to three
  services. A degraded day is a short bar, a down day flat. As upstream
  draws it, made-up days slide in one at a time; give each service its
  `history` and it stands still on yours, for a real status board.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): the
  board is drawn anew from them, a new day added to a history showing at
  once.

    * `services` - the services' names, up to three (more are cut), each
      cut to 24 characters. Fewer sit in the middle of the frame. Default
      `["api", "website", "database"]`.
    * `history` - for each service, in the order of `services`, its daily
      uptime in percent, oldest first, the last being today: a day of 99.95%
      or more is up, of 97% or more degraded, and less is an outage. Days
      before the first are left blank, and a service without a history (or
      an empty one) plays upstream's. Its state today, its headline and its
      footer's uptime follow the days shown. Default `[]`.
    * `days` - how many days the bars span, 20 to 196; the frame is four
      columns wider, 15 rows tall, and labels that do not fit are cut.
      Default 60.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `title.ok`, `title.warn`, `title.fail` - the headline ("all systems
      operational", "degraded performance", "partial outage"), by the worst
      state today: green, yellow and red.
    * `label` - a service's name.
    * `status.ok`, `status.warn`, `status.fail` - its state today
      (operational, degraded, outage): green, yellow and red.
    * `day.up`, `day.degraded`, `day.down` - its days: green, yellow and
      red.
    * `scale` - under the bar, the span's ends ("60 days ago", "today"),
      grey.
    * `rule` - the dotted leaders between them, grey.
    * `value` - the uptime over the days shown; the word "uptime" after it
      is a `label`.

  A state cut at the frame's edge to a letter that could begin two words
  (`o`) is in no part.

  ## Keys and clicks

  It takes none: it shows uptime, and `Ascii.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still
  tells your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): a service's state, say, or one of its days.

  ## Screen readers

  `Ascii.describe/1` tells each service given a history its state today
  and its uptime over the days shown: "uptime: api operational, 100.00%
  over 60 days; database outage, 99.85% over 60 days". Without a history,
  it gives the piece's name and note.

  ## Example

  ```elixir
  up = List.duplicate(100, 59)
  history = [up ++ [100], up ++ [98.5], up ++ [91.0]]
  options = %{services: ["api", "website", "database"], history: history}
  board = Ascii.new!("uptime-bar", options: options, parts: true)

  {frame, board} = Ascii.frame(board, 0.0)
  frame.text =~ "partial outage"
  #=> true

  Ascii.describe(board)
  #=> "uptime: api operational, 100.00% over 60 days; website degraded, 99.97% over 60 days; database outage, 99.85% over 60 days"

  # The next day: the database is back.
  board = Ascii.put_options!(board, history: [up ++ [100], up ++ [98.5], up ++ [91.0, 100]])
  {frame, _board} = Ascii.frame(board, 1.0)
  frame.text =~ "degraded performance"
  #=> true
  ```

  ```heex
  <Ascii.Phoenix.live_player id="status" piece="uptime-bar" options={%{services: @names, history: @history}} parts />
  ```

  Ported from `src/pieces/uptime-bar.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}
  alias Ascii.Kit.Text

  @meta %Ascii.Meta{
    name: "uptime bar",
    category: :data,
    note: "60-day uptime bars for three services, a new day slides in",
    cols: 64,
    rows: 15,
    fps: 8,
    options: %{services: ["api", "website", "database"], history: [], days: 60},
    bounds: %{days: {20, 196}},
    shapes: %{history: [[0.0]]},
    parts: [
      {"title.ok", "#3fb950"},
      {"title.warn", "#d29922"},
      {"title.fail", "#f85149"},
      {"label", nil},
      {"status.ok", "#3fb950"},
      {"status.warn", "#d29922"},
      {"status.fail", "#f85149"},
      {"day.up", "#3fb950"},
      {"day.degraded", "#d29922"},
      {"day.down", "#f85149"},
      {"scale", "#8b949e"},
      {"rule", "#8b949e"},
      {"value", nil}
    ]
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

  # This port's own: in words, each service given a history, as its bar
  # and footer have it: today's state, and the uptime over the days shown.
  @impl true
  def describe(%{history: []}), do: nil

  def describe(%{services: services, history: history} = options) do
    {cols, _rows} = size(options)
    w = cols - 4

    told =
      for {name, h} <- services |> Enum.take(@max) |> Enum.zip(history), h != [] do
        shown = Enum.take(h, -w)
        state = elem({"outage", "degraded", "operational"}, state_of(List.last(shown)))
        pct = JSMath.to_fixed(Enum.sum(shown) / length(shown), 2)
        days = if length(shown) == 1, do: "1 day", else: "#{length(shown)} days"
        "#{Text.slice(name, 0, 24)} #{state}, #{pct}% over #{days}"
      end

    if told != [], do: "uptime: " <> Enum.join(told, "; ")
  end

  # This port's own: the parts of a frame, read off its rows, which sit
  # where frame/3 puts them for the services in the options: the headline,
  # then for each service its name and state, its bar and its footer. A
  # day's state is in its glyph, whichever half of the cell it fills.

  @days for glyphs <- [@bar, @mid],
            {glyph, name} <-
              Enum.zip(Tuple.to_list(glyphs), ["day.down", "day.degraded", "day.up"]),
            into: %{},
            do: {glyph, name}

  @titles %{"a" => "title.ok", "d" => "title.warn", "p" => "title.fail"}
  @states [{"operational", "status.ok"}, {"degraded", "status.warn"}, {"outage", "status.fail"}]
  @text ~r/^( *)(.*?)( *)$/u
  @footer ~r/\d+ days ago|·+|\S+%|uptime|today/u

  @impl true
  def parts(%{lines: lines}, %{services: services}) do
    # As init/1 has them.
    names = services |> Enum.take(@max) |> Enum.map(&Text.slice(&1, 0, 24))
    top = 1 + (@max - length(names)) * 2
    names = List.to_tuple(names)

    for {line, y} <- Enum.with_index(lines) do
      at = y - top - 2

      cond do
        y == top ->
          headline(line)

        at >= 0 and div(at, 4) < tuple_size(names) ->
          service(line, rem(at, 4), elem(names, div(at, 4)))

        true ->
          Parts.line(line, nil)
      end
    end
  end

  # The headline, its first letter enough to tell which it is.
  defp headline(<<"  ", first::utf8, _::binary>> = line),
    do: Parts.captures(line, @text, [nil, Map.get(@titles, <<first::utf8>>), nil])

  defp headline(line), do: Parts.line(line, nil)

  # A service's name and its state (after a gap, and maybe cut), its bar, its footer.
  defp service(line, 0, name) do
    {margin, rest} = line |> String.to_charlist() |> Enum.split(2)
    {label, rest} = Enum.split(rest, Text.length(name))
    rest = List.to_string(rest)
    [gap, word, trail] = Regex.run(@text, rest, capture: :all_but_first)

    Parts.merge([
      {nil, List.to_string(margin)},
      {"label", List.to_string(label)},
      {nil, gap},
      {state(word), word},
      {nil, trail}
    ])
  end

  defp service(line, 1, _name), do: Parts.chars(line, &Map.get(@days, &1))

  defp service(line, 2, _name), do: Parts.matches(line, @footer, &footer/1)

  defp service(line, _blank, _name), do: Parts.line(line, nil)

  # The state a word, or what is left of it, can only be.
  defp state(""), do: nil

  defp state(word) do
    case for {state, name} <- @states, String.starts_with?(state, word), do: name do
      [name] -> name
      _ -> nil
    end
  end

  defp footer("·" <> _), do: "rule"
  defp footer("uptime"), do: "label"

  defp footer(text) do
    if String.ends_with?(text, "%"), do: "value", else: "scale"
  end
end
