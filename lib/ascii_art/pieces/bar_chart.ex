defmodule AsciiArt.Pieces.BarChart do
  @moduledoc """
  Bars easing between three datasets, values riding on top.

  A vertical bar chart with a value axis, gridlines and category labels. The
  bars ease from one dataset to the next with their values on top. As
  upstream draws it, three weeks of visits take turns; give it datasets of
  your own and it charts them, one standing still or several in turn.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): the bars
  ease from what they showed to the new values, so new data as it comes
  reads as a change rather than a jump.

    * `title` - the heading, over the chart on the left. Default
      `"visits by day"`.
    * `labels` - the categories under the bars, a bar each, from the left.
      Default the days of the week.
    * `datasets` - each a map of its `name` and its `values`, a number a
      label, up to a billion either way. One dataset stands still; several
      take turns, their names in a legend on the right, the one shown in
      brackets. A dataset without values draws zeros, and no datasets draw
      no bars. Default upstream's three weeks.
    * `cols` - the frame's width, 30 to 200; upstream's 60 by default, for
      more bars than that holds. It is always 19 rows tall. A line longer
      than the width is cut at its edge.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `AsciiArt.Ink`); part by part with `:parts` (see `AsciiArt.Parts`),
  `parts: true` taking the colours suggested here:

    * `title` - the heading.
    * `legend` - the datasets' names, grey; `legend.active`, the one shown,
      in its brackets, blue.
    * `scale` - the numbers up the side, grey.
    * `axis` - the axis, grey.
    * `grid` - the dashed gridlines, grey.
    * `bar` - the bars, blue; `bar.1`, `bar.2` and on, a bar each from the
      left, to colour them one by one.
    * `value` - the numbers riding on the bars.
    * `label` - the categories under them.

  ## Keys and clicks

  It takes none: it shows data, and `AsciiArt.handle_event/2` ignores every
  event. A Phoenix player given `interactive` and `notify` still tells your
  LiveView where it was clicked, and on which part (`AsciiArt.part_at/4`):
  `bar.3`, say, for the third bar, or its `label`.

  ## Screen readers

  `AsciiArt.describe/1` reads its title and data, its options being its
  data even as upstream gives them: one dataset's bars, as "signups: mon
  12, tue 30, wed 18" (the first eight, then how many more), or each of
  several datasets' highest, as "visits by day, 3 datasets in turn: week 1,
  highest fri 540; …".

  ## Example

  ```elixir
  signups = %{name: "this week", values: [12, 30, 18]}
  options = %{title: "signups", labels: ~w(mon tue wed), datasets: [signups]}
  chart = AsciiArt.new!("bar-chart", options: options, parts: true)

  AsciiArt.describe(chart)
  #=> "signups: mon 12, tue 30, wed 18"

  chart = AsciiArt.put_options!(chart, datasets: [%{signups | values: [12, 30, 41]}])
  {frame, _chart} = AsciiArt.frame(chart, 2.0)
  frame.text =~ "41"
  #=> true
  ```

  ```heex
  <AsciiArt.Phoenix.live_player id="signups" piece="bar-chart" options={%{title: "signups", labels: @days, datasets: [%{name: "this week", values: @counts}]}} parts />
  ```

  Ported from `src/pieces/bar-chart.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath, Parts}
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
    bounds: %{cols: {30, 200}, datasets: %{values: {-1.0e9, 1.0e9}}},
    parts: [
      {"title", nil},
      {"legend", "#8b949e"},
      {"legend.active", "#58a6ff"},
      {"scale", "#8b949e"},
      {"axis", "#8b949e"},
      {"grid", "#8b949e"},
      {"bar", "#58a6ff"},
      {"value", nil},
      {"label", nil}
    ]
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

  # This port's own: in words, the title and the data. One dataset is its
  # bars, the first eight; several are each one's highest bar. A bar with
  # no value is zero, as the chart draws it.
  @impl true
  def describe(%{title: title, labels: labels, datasets: datasets}) do
    name = if title == "", do: "bar chart", else: Text.slice(title, 0, 40)
    labels = Enum.map(labels, &Text.slice(&1, 0, 16))

    case datasets do
      [] -> name <> ": no data"
      [one] -> name <> ": " <> bars(labels, one)
      many -> "#{name}, #{length(many)} datasets in turn: " <> highest(labels, many)
    end
  end

  defp bars([], _dataset), do: "no bars"

  defp bars(labels, dataset) do
    pairs = labels |> Enum.zip(values(dataset, labels)) |> Enum.map(&bar/1)
    more = length(pairs) - 8
    Enum.join(Enum.take(pairs, 8), ", ") <> if(more > 0, do: ", and #{more} more", else: "")
  end

  defp highest(labels, datasets) do
    told =
      datasets
      |> Enum.take(3)
      |> Enum.map_join("; ", fn dataset ->
        named = dataset |> Map.get(:name, "undefined") |> Text.slice(0, 16)

        case labels
             |> Enum.zip(values(dataset, labels))
             |> Enum.max_by(&elem(&1, 1), fn -> nil end) do
          nil -> named
          top -> named <> ", highest " <> bar(top)
        end
      end)

    more = length(datasets) - 3
    told <> if(more > 0, do: "; and #{more} more", else: "")
  end

  defp values(dataset, labels) do
    values = Map.get(dataset, :values, [])
    values ++ List.duplicate(0, max(length(labels) - length(values), 0))
  end

  defp bar({label, v}), do: String.trim(label <> " " <> JSMath.to_string(v))

  # This port's own: the parts of a frame, read off its lines with the
  # layout init/1 makes for these options. What init/1 writes (the title,
  # scale, axis and labels) is its part where the frame still shows it;
  # the legend is where frame/3 puts it, the shown dataset's name in
  # brackets. Bars are theirs by column, from the axis up; a value is the
  # number centred on the row over its bar's top, as frame/3 writes it.
  # Bars easing down from past a new top run over everything above them.

  @bar ["█" | Tuple.to_list(@eighths)]
  @bar_points @bar |> Enum.join() |> String.to_charlist()
  @numeral ~w(0 1 2 3 4 5 6 7 8 9 -)

  @impl true
  def parts(%{lines: lines, cols: cols}, options) do
    %{base: base, names: names, bx: bx, ax: ax, pw: pw} = init(options)

    # The rows a value or the legend can be on, by cell.
    plot =
      lines
      |> Enum.take(@ay)
      |> Enum.map(&(&1 |> Text.chars() |> List.to_tuple()))
      |> List.to_tuple()

    ctx = %{
      base: base,
      ax: ax,
      bars:
        for(
          {x, n} <- Enum.with_index(bx, 1),
          c <- x..(x + @bw - 1),
          into: %{},
          do: {c, "bar.#{n}"}
        ),
      values: bx |> Enum.flat_map(&value_cells(plot, &1, cols)) |> MapSet.new(),
      legend: legend(elem(plot, 1), names, ax + pw + 1, cols)
    }

    for {line, r} <- Enum.with_index(lines), do: Parts.cells(line, &cell_part(&1, &2, r, ctx))
  end

  # Spaces are only ever in the title, the legend or a label; gridlines
  # only between the axis's ends.
  defp cell_part(?\s, _c, r, _ctx) when r != 1 and r != @ay + 1, do: nil
  defp cell_part(?┈, _c, r, _ctx) when r >= 4 and r < @ay, do: "grid"

  defp cell_part(cp, c, r, %{bars: bars} = ctx) when cp in @bar_points and r <= @ay do
    Map.get_lazy(bars, c, fn -> other_part(<<cp::utf8>>, c, r, ctx) end)
  end

  defp cell_part(cp, c, r, ctx), do: other_part(<<cp::utf8>>, c, r, ctx)

  defp other_part(ch, c, r, ctx) do
    cond do
      MapSet.member?(ctx.values, {c, r}) -> "value"
      r == 1 and Map.has_key?(ctx.legend, c) -> Map.fetch!(ctx.legend, c)
      Grid.get(ctx.base, c, r, nil) == ch -> written(c, r, ctx.ax)
      true -> nil
    end
  end

  # What init/1 writes, by where it is.
  defp written(_c, 1, _ax), do: "title"
  defp written(_c, r, _ax) when r == @ay + 1, do: "label"
  defp written(c, _r, ax) when c < ax, do: "scale"
  defp written(_c, _r, _ax), do: "axis"

  # The cells of a bar's value: a whole number on the row over the bar's
  # top, always over its second column, centred on the bar.
  defp value_cells(plot, x, cols) do
    r = top(plot, x + 1, @ay - 1, cols) - 1

    with true <- r >= 0,
         row = elem(plot, r),
         true <- numeral?(row, x + 1, cols) do
      from = reach(row, x + 1, -1, cols)
      to = reach(row, x + 1, 1, cols)

      if from == x + JSMath.floor((@bw - (to - from + 1)) / 2),
        do: for(c <- from..to, do: {c, r}),
        else: []
    else
      _ -> []
    end
  end

  # The top of a bar's column: bar all the way down from it to the axis.
  defp top(plot, c, r, cols) when r >= 0 and c >= 0 and c < cols do
    if elem(elem(plot, r), c) in @bar, do: top(plot, c, r - 1, cols), else: r + 1
  end

  defp top(_plot, _c, r, _cols), do: r + 1

  defp numeral?(row, c, cols), do: c >= 0 and c < cols and elem(row, c) in @numeral

  defp reach(row, c, step, cols) do
    if numeral?(row, c + step, cols), do: reach(row, c + step, step, cols), else: c
  end

  # The legend's cells as frame/3 lays it out, each the part it is in where
  # the frame still shows it: the shown dataset's name and its brackets,
  # told by them, and the others' names.
  defp legend(row, names, right, cols) do
    start = right - (names |> Enum.map(&(Text.length(&1) + 3)) |> Enum.sum()) + 1

    {tabs, _} =
      Enum.map_reduce(names, start, fn name, s ->
        n = Text.length(name) + 2
        {tab(name, shown?(row, s, s + n - 1, cols)), s + n + 1}
      end)

    tabs
    |> Enum.intersperse([{nil, " "}])
    |> Enum.concat()
    |> Enum.with_index(start)
    |> Enum.reduce(%{}, fn {{name, ch}, c}, cells ->
      if char(row, c, cols) == ch, do: Map.put(cells, c, name), else: cells
    end)
  end

  defp shown?(row, first, last, cols) do
    case {char(row, first, cols), char(row, last, cols)} do
      {"[", _} -> true
      {_, "]"} -> true
      {" ", _} -> false
      {_, " "} -> false
      _ -> nil
    end
  end

  # A tab's cells and their parts; one that cannot be told is a gap.
  defp tab(name, true),
    do: [{"legend.active", "["} | chars(name, "legend.active")] ++ [{"legend.active", "]"}]

  defp tab(name, false), do: [{nil, " "} | chars(name, "legend")] ++ [{nil, " "}]
  defp tab(name, nil), do: List.duplicate({nil, :unknown}, Text.length(name) + 2)

  defp chars(name, part), do: for(ch <- Text.chars(name), do: {part, ch})

  defp char(row, c, cols) when c >= 0 and c < cols, do: elem(row, c)
  defp char(_row, _c, _cols), do: nil
end
