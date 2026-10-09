defmodule Ascii.Pieces.SplitFlap do
  @moduledoc """
  A departures board whose flaps riffle to each new line.

  An airport departures board. When a flight leaves, every row moves up and
  each flap riffles through its drum, one card at a time, to land. Give it
  your own departures: trains, buses, deploys, a queue.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): the
  board starts afresh with them, from its first board.

    * `title` - the board's heading, in upper case, spaced out, up to 18
      characters. Default `"departures"`.
    * `start` - the clock on the first board, `"HH:MM"`; after that the
      clock follows the departures. Not a time, and the first board's clock
      follows them too. Default `"14:03"`.
    * `flights` - the departures, in order, each `[time, destination, gate,
      remark]`: a time `"HH:MM"` (past midnight if it comes before the one
      above), a destination of up to 9 characters, a gate of up to 3, and a
      remark of up to 9. Flaps carry A to Z, 0 to 9 and `. - / ' &`; any
      other character shows a blank card. A remark of "on time", or none,
      turns to "gate open", "boarding" and "last call" as its time nears;
      any other ("delayed", "cancelled") stays. Six rows show; every six
      seconds the first leaves and the rest move up, the clock and remarks
      moving on between, and the list comes round again. A flight without a time is left out, and with none left
      the board plays upstream's. Default: twelve flights from 14:05.

  The board is always 61 by 18.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `frame` - the board's border, grey.
    * `title` - the heading.
    * `clock` - the clock at the top right, yellow.
    * `label` - the columns' headings, grey.
    * `time`, `destination`, `gate` - a flight's.
    * `remark`, and `remark.<text>` by what it says once its flaps are
      still, in lower case with runs of other characters as `_`:
      `remark.on_time` green, `remark.gate_open` and `remark.boarding`
      cyan, `remark.last_call` orange, `remark.delayed` yellow,
      `remark.cancelled` red, and a remark of the options' own, whole, as
      `remark.gate_closed` for "gate closed".
    * `flap` - the split beneath each flap, grey.
    * `flipping` - a flap mid-riffle, and the card falling over its split,
      yellow.

  ## Keys and clicks

  It takes none: it is a board to read, and `Ascii.handle_event/2`
  ignores every event. A Phoenix player given `interactive` and `notify`
  still tells your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): a destination, say, and its text.

  ## Screen readers

  `Ascii.describe/1` reads the title and clock, then the first three
  flights, each its time, destination, gate and remark: "trains at 09:00:
  09:10 berlin, gate a3; 09:25 madrid, gate b7, delayed; 09:40 rome, gate
  c1, gate closed", with "and N more" after. Without flights, it says
  "no flights".

  ## Example

  ```elixir
  flights = [
    ["09:10", "berlin", "a3", ""],
    ["09:25", "madrid", "b7", "delayed"],
    ["09:40", "rome", "c1", "gate closed"]
  ]

  board = Ascii.new!("split-flap", options: %{title: "trains", start: "09:00", flights: flights}, parts: true)
  {frame, board} = Ascii.frame(board, 0.0)
  frame.text =~ "B E R L I N"
  #=> true

  Ascii.describe(board)
  #=> "trains at 09:00: 09:10 berlin, gate a3; 09:25 madrid, gate b7, delayed; 09:40 rome, gate c1, gate closed"
  ```

  ```heex
  <Ascii.Phoenix.live_player id="board" piece="split-flap" options={%{title: "deploys", flights: @queue}} parts />
  ```

  Ported from `src/pieces/split-flap.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}
  alias Ascii.Kit.{Grid, Text}
  import Bitwise, only: [band: 2, bxor: 2, >>>: 2]

  @meta %Ascii.Meta{
    name: "split-flap",
    category: :type,
    note: "a departures board whose flaps riffle to each new line",
    cols: 61,
    rows: 18,
    fps: 15,
    options: %{
      title: "departures",
      start: "14:03",
      flights: [
        ["14:05", "lisbon", "a4", "on time"],
        ["14:15", "oslo", "b12", "on time"],
        ["14:20", "nairobi", "c7", "delayed"],
        ["14:35", "lima", "a9", "on time"],
        ["14:40", "reykjavik", "d21", "on time"],
        ["14:50", "seoul", "b3", "on time"],
        ["15:00", "marrakesh", "c14", "cancelled"],
        ["15:05", "helsinki", "a2", "on time"],
        ["15:20", "auckland", "d8", "on time"],
        ["15:25", "kyoto", "b16", "delayed"],
        ["15:35", "cape town", "c11", "on time"],
        ["15:45", "montreal", "a6", "on time"]
      ]
    },
    parts: [
      {"frame", "#8b949e"},
      {"title", nil},
      {"clock", "#d29922"},
      {"label", "#8b949e"},
      {"time", nil},
      {"destination", nil},
      {"gate", nil},
      {"remark", nil},
      {"remark.on_time", "#3fb950"},
      {"remark.gate_open", "#39c5cf"},
      {"remark.boarding", "#39c5cf"},
      {"remark.last_call", "#db6d28"},
      {"remark.delayed", "#d29922"},
      {"remark.cancelled", "#f85149"},
      {"flap", "#8b949e"},
      {"flipping", "#d29922"}
    ]
  }

  # The cards on each kind of flap's drum, in the order they turn up.
  @text " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-/'&"
  @digits " 0123456789"
  # Seconds per board: a departure, then a clock and remarks update; the first
  # flip, after a settled first frame; cards per second.
  @step 3
  @lead 0.8
  @rate 30
  @shown 6

  @impl true
  def meta, do: @meta

  defp hash(a, b, c) do
    h =
      band(
        Int32.umul(Int32.u32(a), 374_761_393) + Int32.umul(Int32.u32(b), 668_265_263) +
          Int32.umul(Int32.u32(c), 2_246_822_519),
        0xFFFFFFFF
      )

    h = Int32.umul(bxor(h, h >>> 13), 1_274_126_177)
    bxor(h, h >>> 16) / 4_294_967_296
  end

  # A time of day in minutes, or nil where upstream's is NaN.
  defp minutes(s) when is_binary(s) do
    case Regex.run(~r/\A(\d{1,2}):(\d{2})\z/, js_trim(s)) do
      [_, h, m] -> String.to_integer(h) * 60 + String.to_integer(m)
      nil -> nil
    end
  end

  defp minutes(_s), do: nil

  # JS's String.prototype.trim, which takes off WhiteSpace and LineTerminator.
  defp js_trim(s) do
    String.replace(
      s,
      ~r/\A[\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]+|[\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]+\z/u,
      ""
    )
  end

  defp hhmm(m) do
    m = Integer.mod(m, 1440)
    pad2(div(m, 60)) <> pad2(rem(m, 60))
  end

  defp pad2(n), do: n |> Integer.to_string() |> Text.pad_start(2, "0")

  defp up(nil), do: ""
  defp up(s), do: String.upcase(s)

  @impl true
  def init(%{title: title, start: start, flights: flights}) do
    %{cols: cols, rows: rows} = @meta
    list = Enum.filter(flights, &(is_list(&1) and minutes(List.first(&1)) != nil))
    list = if list == [], do: @meta.options.flights, else: list
    n = length(list)

    # Times run forward through the list, past midnight if they wrap, and the
    # list comes round again one lap later.
    at =
      list
      |> Enum.reduce([], fn f, at ->
        m = minutes(hd(f))
        [forward(m, List.first(at)) | at]
      end)
      |> Enum.reverse()

    first = hd(at)
    last = List.last(at)
    lap = last - first + if(n > 1, do: max(5, JSMath.round((last - first) / (n - 1))), else: 30)

    board = %{
      at: List.to_tuple(at),
      list: List.to_tuple(list),
      n: n,
      lap: lap,
      opening: minutes(start)
    }

    fields = fields(n)

    %{board: board, fields: fields, base: base(title, fields, n, cols, rows)}
  end

  defp forward(m, nil), do: m
  defp forward(m, prev) when m < prev, do: forward(m + 1440, prev)
  defp forward(m, _prev), do: m

  # Every run of flaps: {row, first column, tiles, drum, what it shows}.
  defp fields(n) do
    cols = @meta.cols

    clock = [
      {1, cols - 11, 2, @digits, :clock_hh},
      {1, cols - 11 + 6, 2, @digits, :clock_mm}
    ]

    rows =
      for i <- 0..(@shown - 1) do
        r = 5 + i * 2
        live = i < n

        [
          {r, 2, 2, @digits, {:hh, i, live}},
          {r, 8, 2, @digits, {:mm, i, live}},
          {r, 14, 9, @text, {:dest, i, live}},
          {r, 34, 3, @text, {:gate, i, live}},
          {r, 42, 9, @text, {:remark, i, live}}
        ]
      end

    for {r, c, len, drum, what} <- clock ++ List.flatten(rows) do
      {r, c, len, drum |> String.codepoints() |> List.to_tuple(), what}
    end
  end

  # The fixed parts of the board: frame, labels, colons and the split beneath each tile.
  defp base(title, fields, n, cols, rows) do
    edge = fn l, r -> l <> String.duplicate("─", cols - 2) <> r end
    side = "│" <> String.duplicate(" ", cols - 2) <> "│"

    g =
      Enum.reduce(0..(rows - 1), Grid.new(cols, rows), fn r, g ->
        line =
          cond do
            r == 0 -> edge.("╭", "╮")
            r == 3 -> edge.("├", "┤")
            r == rows - 1 -> edge.("╰", "╯")
            true -> side
          end

        Grid.put_string(g, 0, r, line)
      end)

    put = fn g, r, c, s ->
      s
      |> Text.chars()
      |> Enum.with_index(c)
      |> Enum.reduce(g, fn {ch, x}, g -> if x < cols - 1, do: Grid.put(g, x, r, ch), else: g end)
    end

    g = put.(g, 1, 2, title |> up() |> Text.slice(0, 18) |> Text.chars() |> Enum.join(" "))
    g = put.(g, 4, 2, "time")
    g = put.(g, 4, 14, "destination")
    g = put.(g, 4, 34, "gate")
    g = put.(g, 4, 42, "remarks")

    g =
      for {r, c, len, _, _} <- fields, i <- 0..(len - 1), reduce: g do
        g -> Grid.put(g, c + 2 * i, r + 1, "▔")
      end

    for i <- -1..(@shown - 1), i < n, reduce: g do
      g -> put.(g, if(i < 0, do: 1, else: 5 + i * 2), if(i < 0, do: cols - 7, else: 6), ":")
    end
  end

  defp minute(%{at: at, n: n, lap: lap}, j),
    do: elem(at, Integer.mod(j, n)) + Integer.floor_div(j, n) * lap

  defp flight(%{list: list, n: n}, j), do: elem(list, Integer.mod(j, n))

  # Board s lists flights from s / 2. On even boards one has just left; on odd
  # ones the clock has moved on to just before the next goes.
  defp first(s), do: Integer.floor_div(s, 2)

  defp clock(%{opening: opening}, 1) when opening != nil, do: opening

  defp clock(board, s) do
    if rem(s, 2) != 0,
      do: minute(board, first(s)) - 2,
      else: minute(board, first(s) - 1) + 1
  end

  defp text(board, :clock_hh, s), do: board |> clock(s) |> hhmm() |> Text.slice(0, 2)
  defp text(board, :clock_mm, s), do: board |> clock(s) |> hhmm() |> Text.slice(2)
  defp text(_board, {_, _, false}, _s), do: ""

  defp text(board, {:hh, i, true}, s),
    do: board |> minute(first(s) + i) |> hhmm() |> Text.slice(0, 2)

  defp text(board, {:mm, i, true}, s),
    do: board |> minute(first(s) + i) |> hhmm() |> Text.slice(2)

  defp text(board, {:dest, i, true}, s), do: board |> flight(first(s) + i) |> Enum.at(1) |> up()
  defp text(board, {:gate, i, true}, s), do: board |> flight(first(s) + i) |> Enum.at(2) |> up()

  defp text(board, {:remark, i, true}, s) do
    said = board |> flight(first(s) + i) |> Enum.at(3) |> up() |> js_trim()

    if said != "" and said != "ON TIME" do
      said
    else
      wait = minute(board, first(s) + i) - clock(board, s)

      cond do
        wait <= 3 -> "LAST CALL"
        wait <= 12 -> "BOARDING"
        wait <= 25 -> "GATE OPEN"
        true -> "ON TIME"
      end
    end
  end

  defp index(drum, ch) do
    Enum.find(0..(tuple_size(drum) - 1), 0, &(elem(drum, &1) == ch))
  end

  @impl true
  def frame(%{board: board} = state, t, _env) do
    v = t - @lead + @step
    k = JSMath.floor(v / @step)
    since = v - k * @step
    s = 1 + k

    grid =
      Enum.reduce(state.fields, state.base, fn {r, c, len, drum, what}, grid ->
        to = board |> text(what, s) |> Text.pad_end(len) |> Text.slice(0, len) |> Text.chars()

        from =
          board |> text(what, s - 1) |> Text.pad_end(len) |> Text.slice(0, len) |> Text.chars()

        [from, to]
        |> Enum.zip()
        |> Enum.with_index()
        |> Enum.reduce(grid, fn {{was, now}, i}, grid ->
          flap(grid, r, c, i, index(drum, was), index(drum, now), drum, s, since)
        end)
      end)

    {Grid.to_iodata(grid), nil, state}
  end

  defp flap(grid, r, c, i, a, b, drum, _s, _since) when a == b,
    do: Grid.put(grid, c + 2 * i, r, elem(drum, b))

  defp flap(grid, r, c, i, a, b, drum, s, since) do
    # Each flap starts a touch after its neighbour and turns forward only;
    # while it turns, the falling card hangs over the split.
    size = tuple_size(drum)
    begin = r * 0.02 + (c + 2 * i) * 0.004 + hash(r, c + i, s) * 0.12
    flips = JSMath.floor(max(0, since - begin) * @rate)
    need = rem(b - a + size, size)

    if flips < need do
      grid = if since >= begin, do: Grid.put(grid, c + 2 * i, r + 1, "▀"), else: grid
      Grid.put(grid, c + 2 * i, r, elem(drum, rem(a + flips, size)))
    else
      Grid.put(grid, c + 2 * i, r, elem(drum, b))
    end
  end

  # This port's own: the parts of a frame. The board's layout is fixed, so a
  # cell is in the part of the field it sits in, from the field's first
  # shown flap to its last, gaps and colon included. A flap mid-riffle hangs
  # its falling card, `▀`, over its split: it is flipping, whatever it
  # shows. A remark is named by what it says once none of its flaps is
  # turning, if that is one the board can show (a still remark can be half
  # old and half new, its flaps landing at different times).

  # The columns of each field's flaps, as fields/1 lays them out.
  @clock [50, 52, 56, 58]
  @remark Enum.to_list(42..58//2)
  @fields [
    {"time", [2, 4, 8, 10]},
    {"destination", Enum.to_list(14..30//2)},
    {"gate", [34, 36, 38]},
    {"remark", @remark}
  ]
  # What the board says for a remark that is empty or "on time".
  @statuses ["LAST CALL", "BOARDING", "GATE OPEN", "ON TIME"]
  @js_space ~r/\A[\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]+|[\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]+\z/u
  @not_word ~r/[^a-z0-9]+/

  @impl true
  def parts(%{lines: lines}, options) do
    rows = Enum.map(lines, &(&1 |> String.codepoints() |> List.to_tuple()))
    remarks = remarks(options)
    last = length(lines) - 1

    [lines, rows, tl(rows) ++ [{}]]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.map(fn {{line, row, under}, y} -> row_parts(y, last, line, row, under, remarks) end)
  end

  defp row_parts(y, last, line, _row, _under, _remarks) when y in [0, 3, last],
    do: Parts.line(line, "frame")

  defp row_parts(1, _last, _line, row, under, _remarks) do
    title = for x <- 1..(hd(@clock) - 1), elem(row, x) != " ", do: x

    names =
      case title do
        [] -> edges(row)
        [from | _] -> span(edges(row), from, List.last(title), "title")
      end

    row |> labelled(field(names, row, under, @clock, "clock")) |> Parts.merge()
  end

  defp row_parts(4, _last, line, _row, _under, _remarks), do: Parts.chars(line, &heading/1)

  defp row_parts(y, _last, _line, row, under, remarks)
       when rem(y, 2) == 1 and y >= 5 and y < 5 + 2 * @shown do
    @fields
    |> Enum.reduce(edges(row), fn {name, flaps}, names ->
      field(names, row, under, flaps, field_name(name, row, under, remarks))
    end)
    |> then(&labelled(row, &1))
    |> Parts.merge()
  end

  defp row_parts(_y, _last, line, _row, _under, _remarks), do: Parts.chars(line, &split/1)

  defp heading("│"), do: "frame"
  defp heading(" "), do: nil
  defp heading(_letter), do: "label"

  defp split("│"), do: "frame"
  defp split("▔"), do: "flap"
  defp split("▀"), do: "flipping"
  defp split(_blank), do: nil

  defp edges(row), do: %{0 => "frame", (tuple_size(row) - 1) => "frame"}

  defp labelled(row, names) do
    for {ch, x} <- row |> Tuple.to_list() |> Enum.with_index(), do: {Map.get(names, x), ch}
  end

  defp span(names, from, to, name), do: Enum.reduce(from..to, names, &Map.put(&2, &1, name))

  # A field's cells, from its first shown flap to its last, flipping ones
  # (and blank ones that are turning) apart.
  defp field(names, row, under, flaps, name) do
    turning = Enum.filter(flaps, &(elem(under, &1) == "▀"))
    shown = Enum.filter(flaps, &(elem(row, &1) != " " or &1 in turning))

    case shown do
      [] ->
        names

      [from | _] ->
        names = span(names, from, List.last(shown), name)
        Enum.reduce(turning, names, &Map.put(&2, &1, "flipping"))
    end
  end

  defp field_name("remark", row, under, remarks) do
    said = @remark |> Enum.map_join(&elem(row, &1)) |> String.trim(" ")
    turning? = Enum.any?(@remark, &(elem(under, &1) == "▀"))
    word = if turning?, do: nil, else: Map.get(remarks, said)
    if word in [nil, ""], do: "remark", else: "remark." <> word
  end

  defp field_name(name, _row, _under, _remarks), do: name

  # The remarks the board can show, as it shows them, each to its name: the
  # whole remark in lowercase, runs of other characters as "_". nil for a
  # remark shown as another is. The default flights' count too, as the
  # board falls back on them when no flight given is one it can show.
  defp remarks(%{flights: flights}) do
    given =
      for flight <- flights ++ @meta.options.flights, is_list(flight), do: Enum.at(flight, 3)

    (given ++ @statuses)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn remark, acc ->
      said = said(remark)
      word = said |> String.downcase() |> String.replace(@not_word, "_") |> String.trim("_")
      Map.update(acc, shown(said), word, &if(&1 == word, do: word))
    end)
  end

  defp said(remark) when is_binary(remark),
    do: remark |> String.upcase() |> String.replace(@js_space, "")

  defp said(_none), do: ""

  # A remark as its flaps show it: cut to their number, a character not on
  # the drum as a blank.
  defp shown(said) do
    said
    |> Text.pad_end(length(@remark))
    |> Text.slice(0, length(@remark))
    |> Text.chars()
    |> Enum.map_join(&if(String.contains?(@text, &1), do: &1, else: " "))
    |> String.trim(" ")
  end

  # This port's own: the board, for a screen reader: its title and clock,
  # and the first flights.
  @impl true
  def describe(%{title: title, start: start, flights: flights}) do
    board = Enum.join(Enum.reject([words(title), words(start)], &(&1 == "")), " at ")
    board = if board == "", do: "split-flap", else: board

    case for(f <- flights, said = flight(f), said != "", do: said) do
      [] ->
        board <> ": no flights"

      said ->
        {shown, rest} = Enum.split(said, 3)
        more = if rest == [], do: "", else: "; and #{length(rest)} more"
        board <> ": " <> Enum.map_join(shown, "; ", &String.slice(&1, 0, 80)) <> more
    end
  end

  # Time and destination, gate, remark.
  defp flight(fields) do
    [time, place, gate, remark] =
      fields |> Enum.map(&words/1) |> Enum.concat(["", "", "", ""]) |> Enum.take(4)

    gate = if gate != "", do: "gate " <> gate, else: ""

    [String.trim(time <> " " <> place), gate, remark]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  defp words(s), do: s |> String.split() |> Enum.join(" ")
end
