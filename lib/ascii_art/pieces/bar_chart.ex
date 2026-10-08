defmodule AsciiArt.Pieces.BarChart do
  @moduledoc """
  Bars easing between three datasets, values riding on top.

  A vertical bar chart with a value axis, gridlines and category labels. The
  bars ease from one dataset to the next with their values on top.

  ## Options

  `title`, `labels` and `datasets` are upstream's: one dataset stands
  still, several take turns. For live data, take new datasets up while
  playing (`AsciiArt.put_options/2`) and the bars ease from what they
  showed to the new values. This port adds `cols`, the frame's width, 30 to
  200, for more bars than fit in upstream's 60.

  Ported from `src/pieces/bar-chart.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.{Grid, Text}

  @meta %AsciiArt.Meta{
    name: "bar chart",
    category: :data,
    note: "bars easing between three datasets, values riding on top",
    cols: 60,
    rows: 19,
    fps: 24,
    options: %{
      title: "visits by day",
      labels: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
      datasets: [
        %{name: "week 1", values: [320, 410, 380, 460, 540, 240, 180]},
        %{name: "week 2", values: [210, 480, 300, 560, 390, 340, 150]},
        %{name: "week 3", values: [450, 290, 520, 380, 580, 160, 270]}
      ],
      cols: 60
    },
    bounds: %{cols: {30, 200}}
  }

  @eighths {"▁", "▂", "▃", "▄", "▅", "▆", "▇"}
  # Plot height in rows, and bar width.
  @ph 12
  @bw 4
  # Seconds each dataset rests, then moves; where in the first rest play time begins.
  @hold 1.4
  @move 1.0
  @start 0.8
  # The axis row, which is the zero line.
  @ay 4 + @ph

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{cols: cols}), do: {trunc(cols), @meta.rows}

  # New data while playing: the bars ease from what they showed.
  @impl true
  def update(%{shown: shown}, options) when shown != nil,
    do: %{init(options) | from: shown, since: nil}

  def update(_state, options), do: init(options)

  @impl true
  def init(%{title: title, labels: labels, datasets: datasets} = options) do
    {cols, rows} = size(options)
    n = length(labels)
    # A dataset without values draws zeros; one without a name, as JS prints undefined.
    values = Enum.map(datasets, &Map.get(&1, :values, []))
    names = Enum.map(datasets, &Map.get(&1, :name, "undefined"))
    peak = values |> List.flatten() |> Enum.reduce(1, &max(&2, &1))
    step = nice_step(peak)
    top = JSMath.ceil(peak / step) * step
    ticks = top / step
    tick_labels = for i <- 0..(trunc(ticks + 1) - 1)//1, do: JSMath.to_string(i * step)
    lw = tick_labels |> Enum.map(&Text.length/1) |> Enum.max()

    # Layout: tick labels, the axis, then the bars with a gap's width either side.
    gap = max(1, min(3, JSMath.floor((cols - 4 - lw - n * @bw) / (n + 1))))
    pw = n * @bw + (n + 1) * gap
    x0 = JSMath.floor((cols - (lw + 1 + pw)) / 2)
    ax = x0 + lw
    bx = for i <- 0..(n - 1)//1, do: ax + 1 + gap + i * (@bw + gap)

    base = cols |> Grid.new(rows) |> Grid.put_string(x0, 1, title)
    base = Enum.reduce(4..(@ay - 1)//1, base, &Grid.put(&2, ax, &1, "│"))

    {base, grid_rows} =
      tick_labels
      |> Enum.with_index()
      |> Enum.reduce({base, []}, fn {s, i}, {base, grid_rows} ->
        r = @ay - JSMath.round(i * @ph / ticks)
        base = Grid.put_string(base, ax - 1 - Text.length(s), r, s)
        if i == 0, do: {base, grid_rows}, else: {Grid.put(base, ax, r, "┤"), [r | grid_rows]}
      end)

    base = Grid.put(base, ax, @ay, "└")
    base = Enum.reduce((ax + 1)..(ax + pw)//1, base, &Grid.put(&2, &1, @ay, "─"))

    base =
      labels
      |> Enum.zip(bx)
      |> Enum.reduce(base, fn {s, x}, base ->
        at = x + JSMath.floor((@bw - Text.length(s)) / 2)
        Grid.put_string(base, at, @ay + 1, Text.slice(s, 0, @bw + gap))
      end)

    %{
      base: base,
      names: names,
      values: values |> Enum.map(&List.to_tuple/1) |> List.to_tuple(),
      top: top,
      bx: bx,
      ax: ax,
      pw: pw,
      grid_rows: Enum.reverse(grid_rows),
      shown: nil,
      from: nil,
      since: nil
    }
  end

  # The smallest round step that splits the range into at most four bands.
  defp nice_step(max) do
    raw = max / 4
    mag = :math.pow(10, JSMath.floor(:math.log10(raw)))
    Enum.find_value([1, 2, 2.5, 5, 10], 10 * mag, &if(&1 * mag >= raw, do: &1 * mag))
  end

  defp ease(x) when x < 0.5, do: 4 * x * x * x
  defp ease(x), do: 1 - :math.pow(-2 * x + 2, 3) / 2

  @impl true
  def frame(state, t, _env) do
    %{base: base, names: names, values: values, ax: ax, pw: pw} = state
    cycle = @hold + @move
    tt = t + @start
    k = JSMath.floor(tt / cycle)
    u = max(0, (tt - k * cycle - @hold) / @move)
    {a, b} = {dataset(values, k), dataset(values, k + 1)}
    e = ease(u)
    live = if e < 0.5, do: k, else: k + 1
    live = rem(live, max(tuple_size(values), 1))

    # The dataset names as tabs, the live one in brackets.
    tabs =
      names
      |> Enum.with_index()
      |> Enum.map_join(" ", fn
        {name, ^live} -> "[" <> name <> "]"
        {name, _} -> " " <> name <> " "
      end)

    grid = Grid.put_string(base, ax + pw + 1 - Text.length(tabs), 1, tabs)

    # Easing from the values shown before new data came, if it did.
    since = if state.from, do: state.since || t
    f = if state.from, do: ease(max(0, min(1, (t - since) / @move))), else: 1

    {tops, grid} =
      state.bx
      |> Enum.with_index()
      |> Enum.map_reduce(grid, fn {x, i}, grid ->
        v = at(a, i) * (1 - e) + at(b, i) * e
        v = if f < 1, do: at(state.from, i) * (1 - f) + v * f, else: v
        h = JSMath.round(v / state.top * @ph * 8)
        full = Int32.sar(h, 3)
        part = Int32.band(h, 7)
        {{v, @ay - 1 - full - if(part != 0, do: 1, else: 0), x}, bar(grid, x, full, part)}
      end)

    # Dashed gridlines behind the bars, kept a cell clear of each bar and value.
    grid =
      for r <- state.grid_rows,
          c <- (ax + 1)..(ax + pw)//1,
          not Enum.any?(tops, fn {_, lr, x} -> c >= x - 1 and c <= x + @bw and r >= lr end),
          reduce: grid,
          do: (g -> Grid.put(g, c, r, "┈"))

    grid =
      Enum.reduce(tops, grid, fn {v, lr, x}, grid ->
        label = v |> JSMath.round() |> JSMath.to_string()
        Grid.put_string(grid, x + JSMath.floor((@bw - Text.length(label)) / 2), lr, label)
      end)

    shown = tops |> Enum.map(&elem(&1, 0)) |> List.to_tuple()
    {from, since} = if f < 1, do: {state.from, since}, else: {nil, nil}
    {Grid.to_iodata(grid), nil, %{state | shown: shown, from: from, since: since}}
  end

  # With no datasets there are no values: every bar is zero.
  defp dataset({}, _k), do: {}
  defp dataset(values, k), do: elem(values, rem(k, tuple_size(values)))

  defp bar(grid, x, full, part) do
    grid =
      for r <- 0..(full - 1)//1,
          c <- 0..(@bw - 1),
          reduce: grid,
          do: (g -> Grid.put(g, x + c, @ay - 1 - r, "█"))

    if part == 0,
      do: grid,
      else:
        Enum.reduce(
          0..(@bw - 1),
          grid,
          &Grid.put(&2, x + &1, @ay - 1 - full, elem(@eighths, part - 1))
        )
  end

  defp at(values, i) when i < tuple_size(values), do: elem(values, i)
  defp at(_values, _i), do: 0
end
