defmodule AsciiArt.Pieces.Candlesticks do
  @moduledoc """
  Hollow up candles, solid down ones, the last one forming live.

  A price chart of five-minute candles, hollow when the price rose and solid
  when it fell. The last candle forms live, then the chart steps.

  ## Options

  `start` and `seed` shape upstream's market. This port adds, for real
  prices:

    * `candles` - each `[open, high, low, close]`, oldest first, the last
      being the one now forming. The last 15 show, against the axis; take
      new ones up as they come (`AsciiArt.put_options/2`).
    * `times` - a label for each candle, such as `"09:30"`, shown under every
      fourth (the first five characters).
    * `digits` - decimals in the prices, 0 to 8 (default 2).

  With candles given, the price scale steps by 1, 2, 2.5 or 5 times a power
  of ten, whatever the prices; upstream's steps stop at 100.

  Ported from `src/pieces/candlesticks.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.{Grid, Text}

  @meta %AsciiArt.Meta{
    name: "candlesticks",
    category: :data,
    note: "hollow up candles, solid down ones, the last one forming live",
    cols: 70,
    rows: 22,
    fps: 15,
    options: %{start: 100, seed: 3, candles: [], times: [], digits: 2},
    bounds: %{digits: {0, 8}},
    shapes: %{candles: [[0.0]], times: [""]}
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
    g = Grid.put_string(g, @axis, lr, "├ " <> fmt(last.c, digits))

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

    head =
      "o #{fmt(last.o, digits)}   h #{fmt(last.h, digits)}   l #{fmt(last.l, digits)}   c #{fmt(last.c, digits)}   " <>
        change(last) <> "%"

    {g |> Grid.put_string(0, 0, head) |> Grid.to_iodata(), nil, state}
  end

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

    Enum.reduce(@top..(@top + @h - 1), g, fn r, g ->
      p = top - (r - @top) * step
      major = abs(p / every - JSMath.round(p / every)) < 1.0e-6
      Grid.put_string(g, @axis, r, if(major, do: "┤ " <> fmt(p, digits), else: "│"))
    end)
  end

  defp draw(g, %{o: o, c: c, h: h, l: l}, x, row) do
    rh = row.(h)
    rl = row.(l)
    rt = row.(max(o, c))
    rb = row.(min(o, c))
    g = Enum.reduce(rh..rl//1, g, &Grid.put(&2, x + 1, &1, "│"))

    cond do
      c < o ->
        Enum.reduce(rt..rb//1, g, &Grid.put_string(&2, x, &1, "███"))

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
        g = Enum.reduce((rt + 1)..(rb - 1)//1, g, &Grid.put_string(&2, x, &1, "│ │"))
        Grid.put_string(g, x, rb, "└" <> if(rl > rb, do: "┬", else: "─") <> "┘")
    end
  end

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
end
