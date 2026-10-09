defmodule AsciiArt.Pieces.Candlesticks do
  @moduledoc """
  Hollow up candles, solid down ones, the last one forming live.

  A price chart of five-minute candles, hollow when the price rose and solid
  when it fell. As upstream draws it, a made-up market trades: the last
  candle forms live, then the chart steps. Give it `candles` and it charts
  your prices instead, standing still until you give it more.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): the chart
  is drawn anew from them, so give the whole list again as candles come and
  close.

    * `candles` - your prices, each `[open, high, low, close]`, oldest
      first, the last being the one now forming. The last 15 show, against
      the axis. Default `[]`: upstream's market.
    * `times` - a label a candle, as `"09:30"`, its first five characters
      shown under every fourth candle. Default `[]`.
    * `digits` - decimals in the prices, 0 to 8. Default 2.
    * `start` - the price upstream's market starts from. Default 100.
    * `seed` - the seed of upstream's market, for another walk. Default 3.

  With candles given, the price scale steps by 1, 2, 2.5 or 5 times a power
  of ten, whatever the prices; upstream's steps stop at 100. A price too wide
  for its place, which upstream writes past the frame's edge, is written to
  fit (see `AsciiArt.Kit.Number`): on the axis, and the last price beside
  it, with fewer decimals, then compactly (`16.6M`), the axis's prices all
  alike; in the quote, the four prices alike, when it would run past the
  frame. `start` and the candles take prices up to 10^15 either way. The
  frame is always 70 by 22.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `AsciiArt.Ink`); part by part with `:parts` (see `AsciiArt.Parts`),
  `parts: true` taking the colours suggested here:

    * `label` - the quote's names for its prices, `o`, `h`, `l` and `c`,
      grey.
    * `value` - the quote's prices.
    * `change.up`, `change.down` - the quote's change by its sign, green
      and red (just `change` for an open of zero).
    * `candle.up`, `candle.down` - each candle, wicks and all, hollow and
      green as the price rose, solid and red as it fell.
    * `price` - the last price's line out to the axis and its figure, blue.
    * `axis` - the axis and its ticks, grey.
    * `scale` - the prices and times along it, grey.

  A wick whose body is off the chart, as a far-off `start` can put it, is in
  no part.

  ## Keys and clicks

  It takes none: it shows prices, and `AsciiArt.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still tells
  your LiveView where it was clicked, and on which part
  (`AsciiArt.part_at/4`): a `candle.up`, say, or the `price`.

  ## Screen readers

  `AsciiArt.describe/1` reads the candles given, how many, and the last
  one's time, prices and change: "candlesticks: 2 candles, the last at
  09:35: open 103.00, high 105.00, low 101.00, close 102.50, -0.49%".
  Playing upstream's market, it gives the piece's name and note.

  ## Example

  ```elixir
  candles = [[100, 104, 96, 103], [103, 105, 101, 102.5]]
  chart = AsciiArt.new!("candlesticks", options: %{candles: candles, times: ["09:30", "09:35"]}, parts: true)

  {frame, _chart} = AsciiArt.frame(chart, 0.0)
  frame.text =~ "c 102.50"
  #=> true

  AsciiArt.describe(chart)
  #=> "candlesticks: 2 candles, the last at 09:35: open 103.00, high 105.00, low 101.00, close 102.50, -0.49%"
  ```

  ```heex
  <AsciiArt.Phoenix.live_player id="price" piece="candlesticks" options={%{candles: @candles, times: @times}} parts />
  ```

  Ported from `src/pieces/candlesticks.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath, Parts}
  alias AsciiArt.Kit.{Grid, Number, Text}

  @meta %AsciiArt.Meta{
    name: "candlesticks",
    category: :data,
    note: "hollow up candles, solid down ones, the last one forming live",
    cols: 70,
    rows: 22,
    fps: 15,
    options: %{start: 100, seed: 3, candles: [], times: [], digits: 2},
    bounds: %{digits: {0, 8}, start: {-1.0e15, 1.0e15}, candles: {-1.0e15, 1.0e15}},
    shapes: %{candles: [[0.0]], times: [""]},
    parts: [
      {"label", "#8b949e"},
      {"value", nil},
      {"change.up", "#3fb950"},
      {"change.down", "#f85149"},
      {"candle.up", "#3fb950"},
      {"candle.down", "#f85149"},
      {"price", "#58a6ff"},
      {"axis", "#8b949e"},
      {"scale", "#8b949e"}
    ]
  }

  # Candles on screen, four columns each; seconds per candle; price moves per candle.
  @slots 15
  @period 1.4
  @ticks 10
  # Chart rows.
  @top 2
  @h 17
  @steps [0.05, 0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10, 20, 25, 50]
  # Candles already traded at t = 0.
  @k0 50
  @axis @slots * 4 + 1
  # Cells for a price after the axis's tick.
  @room 70 - @axis - 2

  @impl true
  def meta, do: @meta

  # Steps for prices of any size: 1, 2, 2.5 and 5 times a power of ten.
  @nice for e <- -8..15, m <- [1, 2, 2.5, 5], do: m * :math.pow(10, e)

  @impl true
  def init(%{start: start, seed: seed} = options) do
    model = %{start: start, seed: seed, vol: start * 0.0017}
    # Each candle's path of prices, made in order since it opens at the last close.
    state = paths(%{model: model, paths: %{}, n: 0}, @k0)
    Map.merge(state, %{given: given(options), digits: trunc(options.digits)})
  end

  # Candles given, as upstream's candle maps, with each one's index.
  defp given(%{candles: []}), do: nil

  defp given(%{candles: candles, times: times}) do
    n = length(candles)
    shown = Enum.take(candles, -@slots)

    %{
      candles: Enum.map(shown, &ohlc/1),
      first: n - length(shown),
      times: List.to_tuple(times)
    }
  end

  defp ohlc([o, h, l, c | _]), do: %{o: o, h: h, l: l, c: c}
  defp ohlc([o, h, l]), do: %{o: o, h: h, l: l, c: o}
  defp ohlc([o, h]), do: %{o: o, h: max(o, h), l: min(o, h), c: h}
  defp ohlc([p]), do: %{o: p, h: p, l: p, c: p}
  defp ohlc([]), do: %{o: 0, h: 0, l: 0, c: 0}

  # Extends the cache of paths through candle k.
  defp paths(%{n: n} = state, k) when n > k, do: state

  defp paths(%{model: model, paths: paths, n: n} = state, k) do
    p = if n == 0, do: model.start, else: elem(paths[n - 1], @ticks)
    paths(%{state | paths: Map.put(paths, n, path(model, n, p)), n: n + 1}, k)
  end

  defp path(%{start: start, seed: seed, vol: vol} = model, n, p) do
    trend = trend(model, n)

    {out, _} =
      Enum.map_reduce(1..@ticks, {p, seed * 15_485_863 + n * 2_654_435_761}, fn _, {p, r} ->
        {a, r} = Int32.mulberry32(r)
        {b, r} = Int32.mulberry32(r)
        g = JSMath.sqrt(-2 * :math.log(1 - a)) * :math.cos(2 * :math.pi() * b)
        p = p + (g * vol + trend - (p - start) * 0.006)
        {p, {p, r}}
      end)

    List.to_tuple([p | out])
  end

  defp hash(seed, k), do: (seed * 7919 + k * 104_729) |> Int32.mulberry32() |> elem(0)

  defp trend(%{seed: seed, vol: vol}, k) do
    u = k / 9
    i = JSMath.floor(u)
    f = u - i
    e = f * f * (3 - 2 * f)
    (hash(seed, i) * (1 - e) + hash(seed, i + 1) * e - 0.5) * vol * 0.55
  end

  defp candle(path, upto) do
    p = for i <- 0..upto, do: elem(path, i)
    %{o: elem(path, 0), c: elem(path, upto), h: Enum.max(p), l: Enum.min(p)}
  end

  defp fmt(p, digits), do: JSMath.to_fixed(p, digits)

  defp clock(k) do
    m = rem(9 * 60 + 30 + k * 5, 1440)
    pad2(div(m, 60)) <> ":" <> pad2(rem(m, 60))
  end

  defp pad2(n), do: n |> JSMath.to_string() |> Text.pad_start(2, "0")

  @impl true
  def frame(state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    {cs, first, label, steps, state} = candles(state, t)
    digits = state.digits
    n = length(cs)
    # The slot of the first candle shown: the last sits against the axis.
    slot0 = @slots - n

    # Scale: a round price per row, centred on the finished candles.
    done = if n > 1, do: Enum.take(cs, n - 1), else: cs
    hi = cs |> Enum.map(& &1.h) |> Enum.max()
    lo = cs |> Enum.map(& &1.l) |> Enum.min()
    step = Enum.find(steps, 100, &((hi - lo) / &1 <= @h - 2))
    mid = (Enum.max(Enum.map(done, & &1.h)) + Enum.min(Enum.map(done, & &1.l))) / 2
    top = JSMath.round(mid / step + (@h - 1) / 2) * step

    top =
      min(
        max(top, JSMath.ceil(hi / step) * step),
        JSMath.floor(lo / step) * step + (@h - 1) * step
      )

    row = fn p -> @top + JSMath.round((top - p) / step) end

    g = cols |> Grid.new(rows) |> axis(top, step, steps, digits)

    # The last price as a dotted line out to the axis.
    last = List.last(cs)
    lr = row.(last.c)
    g = Enum.reduce((@slots * 4 - 1)..(@axis - 1)//1, g, &Grid.put(&2, &1, lr, "┄"))
    g = Grid.put_string(g, @axis, lr, "├ " <> price(last.c, digits))

    g =
      cs
      |> Enum.with_index(slot0)
      |> Enum.reduce(g, fn {c, s}, g -> draw(g, c, s * 4, row) end)

    # Time along the bottom, every fourth candle.
    base = @top + @h
    g = Grid.put_string(g, 0, base, String.duplicate("─", @axis))
    g = Grid.put(g, @axis, base, "┘")

    g =
      Enum.reduce(slot0..(@slots - 1)//1, g, fn s, g ->
        k = first + s - slot0

        cond do
          rem(k, 4) != 0 ->
            g

          s == 0 ->
            Grid.put(g, s * 4 + 1, base, "┴")

          true ->
            g |> Grid.put(s * 4 + 1, base, "┴") |> Grid.put_string(s * 4 - 1, base + 1, label.(k))
        end
      end)

    {g |> Grid.put_string(0, 0, headline(last, digits)) |> Grid.to_iodata(), nil, state}
  end

  # The quote along the top. This port's own: one too long for the frame,
  # which upstream writes past its edge, has its prices written to fit
  # (see AsciiArt.Kit.Number), and a change too long, too.
  defp headline(%{o: o, h: h, l: l, c: c} = last, digits) do
    plain = headline([o, h, l, c] |> Enum.map(&fmt(&1, digits)), change(last))

    if Text.length(plain) <= @meta.cols do
      plain
    else
      change = change(last, 8)
      w = div(@meta.cols - 21 - Text.length(change), 4)
      headline(Number.fit_all([o, h, l, c], digits, w), change)
    end
  end

  defp headline([o, h, l, c], change), do: "o #{o}   h #{h}   l #{l}   c #{c}   " <> change <> "%"

  # A price after the axis's tick: as upstream writes it, or (this port's
  # own) written to fit what is left of the row.
  defp price(p, digits), do: Number.fit(p, digits, @room)

  # The candles on show, the index of the first, how to label one, and the
  # steps the scale may take: upstream's market, or the candles given.
  defp candles(%{given: nil} = state, t) do
    live = @k0 + JSMath.floor(t / @period)
    ticks = 1 + JSMath.floor(JSMath.mod(t, @period) / @period * @ticks)
    state = paths(state, live)

    cs =
      for s <- 0..(@slots - 1) do
        k = live - @slots + 1 + s
        candle(state.paths[k], if(k == live, do: ticks, else: @ticks))
      end

    {cs, live - @slots + 1, &clock/1, @steps, state}
  end

  defp candles(%{given: given} = state, _t) do
    times = given.times

    label = fn k ->
      if k < tuple_size(times), do: Text.slice(elem(times, k), 0, 5), else: ""
    end

    {given.candles, given.first, label, @nice, state}
  end

  # Labels at the first round interval at least three rows apart.
  defp axis(g, top, step, steps, digits) do
    every =
      Enum.find(steps, step * 4, fn s ->
        s >= step * 3 - 1.0e-9 and abs(s / step - JSMath.round(s / step)) < 1.0e-6
      end)

    prices = for r <- @top..(@top + @h - 1), do: {r, top - (r - @top) * step}
    majors = for {r, p} <- prices, abs(p / every - JSMath.round(p / every)) < 1.0e-6, do: {r, p}
    labels = Map.new(Enum.zip(Enum.map(majors, &elem(&1, 0)), prices(majors, digits)))

    Enum.reduce(prices, g, fn {r, _p}, g ->
      Grid.put_string(g, @axis, r, if(l = labels[r], do: "┤ " <> l, else: "│"))
    end)
  end

  # The axis's prices as upstream writes them; or (this port's own) all
  # written alike to fit what is left of the row.
  defp prices(majors, digits),
    do: majors |> Enum.map(&elem(&1, 1)) |> Number.fit_all(digits, @room)

  defp draw(g, %{o: o, c: c, h: h, l: l}, x, row) do
    rh = row.(h)
    rl = row.(l)
    rt = row.(max(o, c))
    rb = row.(min(o, c))
    g = Enum.reduce(on_chart(rh, rl), g, &Grid.put(&2, x + 1, &1, "│"))

    cond do
      c < o ->
        Enum.reduce(on_chart(rt, rb), g, &Grid.put_string(&2, x, &1, "███"))

      rt == rb ->
        mark =
          cond do
            rh < rt and rl > rb -> "┼"
            rh < rt -> "┴"
            rl > rb -> "┬"
            true -> "─"
          end

        Grid.put_string(g, x, rt, "├" <> mark <> "┤")

      true ->
        g = Grid.put_string(g, x, rt, "┌" <> if(rh < rt, do: "┴", else: "─") <> "┐")
        g = Enum.reduce(on_chart(rt + 1, rb - 1), g, &Grid.put_string(&2, x, &1, "│ │"))
        Grid.put_string(g, x, rb, "└" <> if(rl > rb, do: "┬", else: "─") <> "┘")
    end
  end

  # Rows `from` to `to` that are in the frame: the grid drops the others,
  # so only these are worth visiting, which matters for a candle millions
  # of rows long, as prices far from the scale make it.
  defp on_chart(from, to), do: max(from, 0)..min(to, @meta.rows - 1)//1

  # The change in percent. Upstream divides by the open, so an open of zero
  # prints JS's NaN or Infinity.
  defp change(%{o: o, c: c}) when o == 0 do
    cond do
      c - o == 0 -> "NaN"
      c - o > 0 -> "+Infinity"
      true -> "-Infinity"
    end
  end

  defp change(%{o: o, c: c}) do
    chg = (c - o) / o * 100
    if(chg >= 0, do: "+", else: "") <> JSMath.to_fixed(chg, 2)
  end

  # The change in at most `width` characters, its sign included.
  defp change(%{o: o} = last, _width) when o == 0, do: change(last)

  defp change(%{o: o, c: c}, width) do
    chg = (c - o) / o * 100
    if chg >= 0, do: "+" <> Number.fit(chg, 2, width - 1), else: Number.fit(chg, 2, width)
  end

  # This port's own: in words, the candles given, the last one's prices.
  @impl true
  def describe(%{candles: []}), do: nil

  def describe(%{candles: candles, times: times, digits: digits}) do
    n = length(candles)
    %{o: o, h: h, l: l, c: c} = last = candles |> List.last() |> ohlc()
    d = trunc(digits)

    at =
      case Enum.at(times, n - 1, "") do
        "" -> ""
        time -> " at " <> Text.slice(time, 0, 16)
      end

    change = if o == 0, do: "", else: ", " <> change(last) <> "%"

    "candlesticks: #{n} candle#{if n == 1, do: "", else: "s"}, the last#{at}: " <>
      "open #{fmt(o, d)}, high #{fmt(h, d)}, low #{fmt(l, d)}, close #{fmt(c, d)}" <> change
  end

  # This port's own: the parts of a frame, read off its cells. Each candle
  # keeps to three of its four columns, so a cell's column says whose it
  # is, and the candle's sides say which way it went: solid down, hollow up.
  # Past the candles are the price line and the axis, each row's label after
  # it; the axis runs along the foot, with the times under its ticks.

  # The quote as frame/3 writes it, or as much of it as the frame's edge
  # leaves, its change then running to the edge; and the part of each word
  # and gap in it.
  @head ~r/^(o)(?:( )(\S+)(?:(   )(h)(?:( )(\S+)(?:(   )(l)(?:( )(\S+)(?:(   )(c)(?:( )(\S+)(?:(   )([-+]\S*?%|NaN%|\S+$))?)?)?)?)?)?)?)?/
  @quote Enum.intersperse(
           ["label", "value", "label", "value", "label", "value", "label", "value", :change],
           nil
         )
  @plot @slots * 4 - 1
  # The axis along the foot, and the times under it.
  @base @top + @h
  @times @base + 1

  @impl true
  def parts(%{lines: [head | _] = lines, t: t}, options) do
    cells = Enum.map(lines, &String.codepoints/1)
    {heading, quoted} = heading(head)
    close = close(options, t)
    ways = ways(cells)

    # Each time's cells: up to five, from two left of its tick.
    times =
      for {"┴", x} <- cells |> Enum.at(@base) |> Enum.with_index(), x > 1, do: (x - 2)..(x + 2)

    for {row, y} <- Enum.with_index(cells) do
      case y do
        0 -> heading ++ chart(Enum.drop(row, quoted), quoted, ways, close, [])
        @base -> foot(row)
        @times -> chart(row, 0, ways, close, times)
        _ -> chart(row, 0, ways, close, [])
      end
      |> Parts.merge()
    end
  end

  # The quote's runs, and how many cells it takes.
  defp heading(head) do
    case Regex.run(@head, head, return: :index) do
      [{0, len} | groups] ->
        runs =
          for {{at, n}, name} <- Enum.zip(groups, @quote), at >= 0 do
            text = binary_part(head, at, n)
            {quoted(name, text), text}
          end

        {runs, len}

      nil ->
        {[], 0}
    end
  end

  defp quoted(:change, "+" <> _), do: "change.up"
  defp quoted(:change, "-" <> _), do: "change.down"
  defp quoted(:change, _text), do: "change"
  defp quoted(name, _text), do: name

  # The last price as frame/3 writes it at the axis, from the candles
  # given or upstream's market at the frame's time.
  defp close(options, t) do
    state = init(options)
    {cs, _first, _label, _steps, _state} = candles(state, t)
    price(List.last(cs).c, state.digits)
  end

  # Which way each slot's candle went, by its sides on the chart, or nil if
  # neither side is on it.
  defp ways(cells) do
    rows = cells |> Enum.slice(1, @base - 1) |> Enum.map(&List.to_tuple/1)

    for s <- 0..(@slots - 1) do
      sides = for row <- rows, x <- [s * 4, s * 4 + 2], elem(row, x) != " ", do: elem(row, x)

      cond do
        "█" in sides -> "candle.down"
        sides != [] -> "candle.up"
        true -> nil
      end
    end
    |> List.to_tuple()
  end

  # A row's cells from column `from`: the candles', the price line's, then
  # the axis and its label; on the times' row, the times.
  defp chart(cells, from, ways, close, times) do
    {plot, label} = Enum.split(cells, max(@axis - from, 0))
    plot = for {ch, x} <- Enum.with_index(plot, from), do: {cell(ch, x, ways, times), ch}
    if from <= @axis, do: plot ++ label(label, close), else: plot ++ [{nil, Enum.join(label)}]
  end

  defp cell(" ", _x, _ways, _times), do: nil

  defp cell(ch, x, ways, times) do
    cond do
      Enum.any?(times, &(x in &1)) -> "scale"
      x < @plot -> if rem(x, 4) != 3, do: elem(ways, div(x, 4))
      ch == "┄" -> "price"
      true -> nil
    end
  end

  defp label(["┤" | rest], _close), do: [{"axis", "┤"} | scale(rest)]
  defp label(["│" | rest], _close), do: [{"axis", "│"}, {nil, Enum.join(rest)}]

  # The last price over the axis: its figure, then what is left of the
  # axis's label it was written over.
  defp label(["├", " " | rest], close) when is_binary(close) do
    n = min(Text.length(close), length(rest))
    {figure, left} = Enum.split(rest, n)
    figure = Enum.join(figure)

    if figure == Text.slice(close, 0, n),
      do: [{"price", "├ " <> figure} | scale(left)],
      else: [{"price", "├"}, {nil, " " <> figure <> Enum.join(left)}]
  end

  defp label(["├" | rest], _close), do: [{"price", "├"}, {nil, Enum.join(rest)}]
  defp label(cells, _close), do: [{nil, Enum.join(cells)}]

  defp scale(cells), do: Enum.map(cells, &{if(&1 != " ", do: "scale"), &1})

  # The axis along the foot, and its corner.
  defp foot(row) do
    {axis, rest} = Enum.split(row, @axis + 1)
    Enum.map(axis, &{if(&1 != " ", do: "axis"), &1}) ++ [{nil, Enum.join(rest)}]
  end
end
