defmodule AsciiArt.Pieces.SplitFlap do
  @moduledoc """
  A departures board whose flaps riffle to each new line.

  An airport departures board. When a flight leaves, every row moves up and
  each flap riffles through its drum, one card at a time, to land.

  `start` is the clock on the first board. Each flight is time, destination,
  gate and remark; "on time" turns to boarding as the time nears.

  Ported from `src/pieces/split-flap.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.{Grid, Text}
  import Bitwise, only: [band: 2, bxor: 2, >>>: 2]

  @meta %AsciiArt.Meta{
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
    }
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
end
