defmodule AsciiArt.Pieces.Gauge do
  @moduledoc """
  Semicircle dial, the needle overshoots each new reading.

  A semicircle dial in half-block pixels, a band filled up to the reading,
  and a needle that springs to each new value, overshoots, and settles. As
  upstream draws it, it plays readings of its own; give it a `value` and it
  shows yours, for a dashboard or a terminal UI.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): a new
  `value` swings the needle from wherever it is, at its speed, overshooting
  and settling on the reading.

    * `value` - the reading, in `min`..`max` units; the readout shows it as
      given (rounded). Default `nil`: upstream's own readings, a new one
      every few seconds.
    * `label` - the line under the readout. Default `"load"`.
    * `unit` - after the readout: `%` and `°` close up to it, anything else
      takes a space. Default `"%"`.
    * `min`, `max` - the scale's ends; numbers stand at each fifth of the
      way between them. Defaults 0 and 100.
    * `cols`, `rows` - the frame's size, 43 to 200 by 15 to 100; upstream's
      55 by 18 by default. The dial is drawn as large as fits, centred, its
      ticks, band and needle the same distance inside the rim as ever: to
      fill a pane in a terminal UI or a cell of a grid.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `AsciiArt.Ink`); part by part with `:parts` (see `AsciiArt.Parts`),
  `parts: true` taking the colours suggested here:

    * `dial` - the rim, grey.
    * `axis` - the ticks at every tenth, grey; `axis.minor`, the dots
      between.
    * `scale` - the numbers, grey.
    * `bar` - the band filled up to the needle, blue; `track`, the rest of
      it, grey.
    * `needle` - the needle, yellow; `needle.hub`, the pivot it turns on.
    * `value`, `unit` - the readout.
    * `label` - the line under it.

  Where the needle crosses a tick without showing on it, the cell is the
  needle's or the tick's as the needle's angle, as far as the picture
  tells it, says; in the few frames it cannot tell, the cell is in no part.

  ## Keys and clicks

  It takes none: it shows a reading, and `AsciiArt.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still tells
  your LiveView where it was clicked, and on which part
  (`AsciiArt.part_at/4`), the needle, say, or the readout.

  ## Screen readers

  `AsciiArt.describe/1` reads the reading, as the readout shows it: "load:
  72%". Playing its own readings, it gives the piece's name and note.

  ## Example

  ```elixir
  gauge = AsciiArt.new!("gauge", options: %{label: "cpu", value: 35}, parts: true)
  gauge = AsciiArt.put_options!(gauge, value: 80)
  {frame, _gauge} = AsciiArt.frame(gauge, 2.0)
  frame.text =~ "80%"
  #=> true

  AsciiArt.describe(gauge)
  #=> "cpu: 80%"
  ```

  ```heex
  <AsciiArt.Phoenix.live_player id="cpu" piece="gauge" options={%{label: "cpu", value: @cpu}} parts />
  ```

  Ported from `src/pieces/gauge.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath, Parts}
  alias AsciiArt.Kit.Text
  import Bitwise, only: [<<<: 2, >>>: 2, |||: 2, &&&: 2, bnot: 1]

  @meta %AsciiArt.Meta{
    name: "gauge",
    category: :data,
    note: "semicircle dial, the needle overshoots each new reading",
    cols: 55,
    rows: 18,
    fps: 30,
    options: %{label: "load", unit: "%", min: 0, max: 100, value: nil, cols: 55, rows: 18},
    bounds: %{cols: {43, 200}, rows: {15, 100}},
    parts: [
      {"dial", "#8b949e"},
      {"axis", "#8b949e"},
      {"axis.minor", nil},
      {"scale", "#8b949e"},
      {"bar", "#58a6ff"},
      {"track", "#8b949e"},
      {"needle", "#d29922"},
      {"needle.hub", nil},
      {"value", nil},
      {"unit", nil},
      {"label", nil}
    ]
  }

  # Seconds per reading; damping (about a quarter overshoot); natural
  # frequency in rad/s.
  @hold 2.6
  @zeta 0.38
  @w0 5.2
  @half {" ", "▀", "▄", "█"}

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{cols: cols, rows: rows}), do: {trunc(cols), trunc(rows)}

  # The dial for a frame: the rim's radius in pixels, the largest that fits
  # (22 at upstream's size, 16 at the least), and the pivot pixel, the dial
  # centred in the frame. A pixel is a cell wide and half a cell tall; the
  # frame is `h` pixels tall. A dial of radius r is 2r + 11 cells wide and
  # (r + 5) / 2 + 5 rows tall, the readout and the label under its pivot,
  # which is in a cell's lower pixel, as upstream's is, so the readout has
  # the ends of the scale beside it.
  defp geometry(options) do
    {cols, rows} = size(options)
    r = min(div(cols - 11, 2), 2 * rows - 14)
    ox = div(cols - (2 * r + 11), 2)
    oy = div(rows - ((r + 5) >>> 1) - 5, 2)
    cy = r + 5 ||| 1
    %{r: r, cx: r + 5 + ox, cy: cy + 2 * oy, cols: cols, rows: rows, h: 2 * rows}
  end

  # The rows of the readout and of the label under it.
  defp readout_row(%{cy: cy}), do: (cy >>> 1) + 2

  # The needle's steps, a quarter pixel apart from 2 pixels out, to 6 short
  # of the rim.
  defp needle_steps(%{r: r}), do: 0..(4 * (r - 8))

  defp angle_of(v), do: :math.pi() * (1 - v / 100)

  defp plot(set, x, y, %{cols: cols, h: h}) do
    c = JSMath.round(x)
    r = JSMath.round(y)

    if c >= 0 and c < cols and r >= 0 and r < h,
      do: MapSet.put(set, c + r * cols),
      else: set
  end

  @impl true
  def init(%{label: label, unit: unit, min: lo, max: hi} = options) do
    %{cols: cols, rows: rows, r: rim, cx: cx, cy: cy} = g = geometry(options)
    text = numbers(lo, hi, g)
    fixed = fixed(g)

    # Pixels that never move, by cell: the top pixel is bit 1, the bottom bit 2.
    k_of = fn c, r ->
      y = 2 * r
      bit(fixed, c + y * cols) ||| bit(fixed, c + (y + 1) * cols) <<< 1
    end

    # A dot between ticks.
    dots =
      for v <- 5..95//10, into: %{} do
        a = angle_of(v)

        {JSMath.round(cx + (rim - 7.5) * :math.cos(a)) +
           JSMath.floor((cy - (rim - 7.5) * :math.sin(a) + 0.5) / 2) * cols, "·"}
      end

    cells =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          i = c + r * cols
          {Map.get(text, i), k_of.(c, r), Map.get(dots, i), band(c, r, g)}
        end
      end

    a = @zeta * @w0
    w = @w0 * :math.sqrt(1 - @zeta * @zeta)

    readings =
      extend(%{targets: %{0 => 55}, states: %{0 => {30, 0}}, n: 1, rand: 42, a: a, w: w}, 4)

    %{
      g: g,
      cells: cells,
      readings: readings,
      live: live(options),
      at: {30.0, 0.0},
      label: label,
      unit: unit,
      lo: lo,
      hi: hi
    }
  end

  # A reading given (this port's `value`): the needle springs to it from
  # where it is, starting at the first frame drawn after.
  defp live(%{value: nil}), do: nil

  defp live(%{value: v, min: lo, max: hi}) do
    target = if hi == lo, do: 0.0, else: (v - lo) / (hi - lo) * 100
    %{value: v, target: max(0.0, min(100.0, target)), from: {0.0, 0.0}, since: nil}
  end

  @impl true
  def update(%{at: at} = state, options) do
    fresh = init(options)

    case {fresh.live, state.live} do
      {nil, _} -> fresh
      # A new reading: from wherever the needle is, at its speed.
      {live, _} -> %{fresh | live: %{live | from: at}, at: at}
    end
  end

  defp bit(set, i), do: if(MapSet.member?(set, i), do: 1, else: 0)

  # The rim, stepping along whichever axis moves faster, a two-pixel tick
  # every 10, and the hub.
  defp fixed(%{r: rim, cx: cx, cy: cy} = g) do
    set =
      Enum.reduce(-rim..rim, MapSet.new(), fn x, set ->
        plot(set, cx + x, cy - :math.sqrt(rim * rim - x * x), g)
      end)

    set =
      Enum.reduce(0..rim, set, fn y, set ->
        x = :math.sqrt(rim * rim - y * y)
        set |> plot(cx - x, cy - y, g) |> plot(cx + x, cy - y, g)
      end)

    set =
      for v <- 0..100//10, r <- [rim - 8, rim - 7], reduce: set do
        set ->
          a = angle_of(v)
          plot(set, cx + r * :math.cos(a), cy - r * :math.sin(a), g)
      end

    for y <- -2..2, x <- -2..2, x * x + y * y <= 5, reduce: set do
      set -> plot(set, cx + x, cy + y, g)
    end
  end

  # The band's cells by angle (upstream's NaN, outside the band, is nil),
  # stored in a Float32Array.
  defp band(c, r, %{r: rim, cx: cx, cy: cy}) do
    dx = c - cx
    dy = cy - (2 * r + 0.5)
    d = JSMath.hypot(dx, dy)

    if dy > -0.6 and d > rim - 4.1 and d < rim - 2.1,
      do: JSMath.fround(:math.atan2(max(0, dy), dx))
  end

  # Numbers every 20 just outside the rim; the two ends sit under it.
  defp numbers(lo, hi, %{r: rim, cx: cx, cy: cy, cols: cols}) do
    for v <- 0..100//20, reduce: %{} do
      text ->
        a = angle_of(v)
        s = JSMath.to_string(JSMath.round(lo + (hi - lo) * v / 100))
        n = Text.length(s)
        side? = rem(v, 100) != 0
        rr = if side?, do: rim + 2.5, else: rim
        x = cx + rr * :math.cos(a) + if(side?, do: n / 2 * :math.cos(a), else: 0)
        y = if side?, do: cy - (rr + 1) * :math.sin(a), else: cy + 3
        c0 = JSMath.round(x - (n - 1) / 2)
        r = JSMath.floor((y + 0.5) / 2)

        s
        |> Text.chars()
        |> Enum.with_index(c0)
        |> Enum.reduce(text, fn {ch, c}, text ->
          if c >= 0 and c < cols, do: Map.put(text, c + r * cols, ch), else: text
        end)
    end
  end

  # Readings and the spring that chases them, solved exactly per reading.
  defp spring(x0, v0, target, s, a, w) do
    aa = x0 - target
    b = (v0 + a * aa) / w
    e = :math.exp(-a * s)
    c = :math.cos(w * s)
    n = :math.sin(w * s)
    {target + e * (aa * c + b * n), e * (-a * (aa * c + b * n) + w * (-aa * n + b * c))}
  end

  defp extend(%{n: n} = readings, k) when n > k, do: readings

  defp extend(%{targets: targets, states: states, n: n, a: a, w: w} = readings, k) do
    last = targets[n - 1]
    {next, rand} = pick(readings.rand, last)
    {x0, v0} = states[n - 1]

    extend(
      %{
        readings
        | targets: Map.put(targets, n, next),
          states: Map.put(states, n, spring(x0, v0, last, @hold, a, w)),
          n: n + 1,
          rand: rand
      },
      k
    )
  end

  defp pick(rand, last) do
    {x, rand} = Int32.mulberry32(rand)
    next = 12 + x * 76
    if abs(next - last) < 22, do: pick(rand, last), else: {next, rand}
  end

  defp value(readings, t) do
    k = JSMath.floor(t / @hold)
    readings = extend(readings, k)
    {x0, v0} = readings.states[k]
    {x, speed} = spring(x0, v0, readings.targets[k], t - k * @hold, readings.a, readings.w)
    {x, speed, readings}
  end

  # The needle: upstream's readings, or the one given.
  defp needle(%{live: nil} = state, t) do
    {x, speed, readings} = value(state.readings, t + @hold - 0.4)
    {x, %{state | readings: readings, at: {x, speed}}}
  end

  defp needle(%{live: live, readings: %{a: a, w: w}} = state, t) do
    since = live.since || t
    {x0, v0} = live.from
    {x, speed} = spring(x0, v0, live.target, max(0.0, t - since), a, w)
    {x, %{state | live: %{live | since: since}, at: {x, speed}}}
  end

  @impl true
  def frame(%{g: %{cols: cols, cx: cx, cy: cy, h: h} = g} = state, t, _env) do
    %{lo: lo, hi: hi} = state
    {v, state} = needle(state, t)
    v = max(-1, min(101, v))
    an = angle_of(v)
    cos = :math.cos(an)
    sin = :math.sin(an)

    needle =
      Enum.reduce(needle_steps(g), %{}, fn j, needle ->
        r = 2 + j * 0.25
        x = JSMath.round(cx + r * cos)
        y = JSMath.round(cy - r * sin)

        if x >= 0 and x < cols and y >= 0 and y < h,
          do: Map.update(needle, x + (y >>> 1) * cols, bit_of(y), &(&1 ||| bit_of(y))),
          else: needle
      end)

    shown =
      case state.live do
        nil -> JSMath.round(lo + (hi - lo) * max(0, min(100, v)) / 100)
        live -> JSMath.round(live.value)
      end

    unit = state.unit

    tail =
      if String.starts_with?(unit, ["%", "°"]) or unit == "", do: unit, else: " " <> unit

    overlay =
      %{}
      |> centre(JSMath.to_string(shown) <> tail, readout_row(g), g)
      |> centre(state.label, readout_row(g) + 1, g)

    edge = an - 0.02

    lines =
      state.cells
      |> Enum.with_index()
      |> Enum.map(fn {row, r} ->
        row
        |> Enum.with_index(r * cols)
        |> Enum.map(fn {cell, i} ->
          Map.get(overlay, i) || cell(cell, Map.get(needle, i, 0), edge)
        end)
      end)

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp bit_of(y), do: if((y &&& 1) == 0, do: 1, else: 2)

  defp cell({nil, k, dot, band}, needle, edge) do
    case k ||| needle do
      0 when dot != nil -> dot
      0 when band == nil -> " "
      0 when band >= edge -> "▓"
      0 -> "░"
      k -> elem(@half, k)
    end
  end

  defp cell({text, _, _, _}, _needle, _edge), do: text

  # The reading given, as the readout shows it, and what it is of.
  @impl true
  def describe(%{value: nil}), do: nil

  def describe(%{value: v, label: label, unit: unit}) do
    name = if String.trim(label) == "", do: @meta.name, else: label
    "#{name}: #{v |> JSMath.round() |> JSMath.to_string()}#{tail(unit)}"
  end

  defp centre(overlay, s, r, %{cols: cols, cx: cx}) do
    s = Text.slice(s, 0, cols)
    c0 = JSMath.round(cx + 0.5 - Text.length(s) / 2)

    s
    |> Text.chars()
    |> Enum.with_index(c0)
    |> Enum.reduce(overlay, fn {ch, c}, overlay ->
      if c >= 0 and c < cols, do: Map.put(overlay, c + r * cols, ch), else: overlay
    end)
  end

  # This port's own: the parts of a frame, read off its lines with the
  # dial's geometry. The numbers and the label are where the options put
  # them, and the readout where it stands. The rest of the dial goes by its
  # glyph, a half block by its pixels: those the dial does not draw are the
  # needle's, and the others the rim's, a tick's or the hub's by how far
  # they are from the pivot. A tick the needle covers without showing is
  # settled by the needle's angle, as far as the pixels in view tell it.

  @glyphs %{?· => "axis.minor", ?▓ => "bar", ?░ => "track"}
  @half_bits %{?▀ => 1, ?▄ => 2, ?█ => 3}
  @digits ~w(0 1 2 3 4 5 6 7 8 9)
  # The angles tried when the span's ends and middle disagree.
  @search 9

  @impl true
  def parts(%{lines: lines}, %{label: label, min: lo, max: hi} = options) do
    g = geometry(options)
    {dial, [readout, under | rest]} = Enum.split(lines, readout_row(g))
    text = numbers(lo, hi, g)
    fixed = fixed(g)

    {rows, seen} =
      dial
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {line, r}, seen ->
        {cells, seen} = dial_row(line, {0, r * g.cols}, {text, fixed, g}, [], seen)
        {{line, cells}, seen}
      end)

    ticks = for {_line, cells} <- rows, {{:tick, pixels}, _} <- cells, uniq: true, do: pixels
    named = tick_parts(ticks, seen, fixed, g)

    Enum.map(rows, fn {line, cells} -> cut(line, cells, named) end) ++
      [readout_parts(readout, text, options, g), label_parts(under, label, g)] ++
      Enum.map(rest, &Parts.line(&1, nil))
  end

  # A dial row's cells by part, neighbours in one part together, each with
  # its length in bytes; a tick the needle may cover waits for tick_parts/3.
  defp dial_row(<<>>, _at, _dial, cells, seen), do: {Enum.reverse(cells), seen}

  defp dial_row(<<cp::utf8, rest::binary>> = line, {c, i}, dial, cells, seen) do
    {name, seen} = dial_cell(cp, c, i, dial, seen)
    size = byte_size(line) - byte_size(rest)

    cells =
      case cells do
        [{^name, n} | cells] -> [{name, n + size} | cells]
        cells -> [{name, size} | cells]
      end

    dial_row(rest, {c + 1, i + 1}, dial, cells, seen)
  end

  defp dial_cell(?\s, _c, _i, _dial, seen), do: {nil, seen}

  defp dial_cell(cp, c, i, {text, fixed, g}, seen) do
    case {Map.get(@glyphs, cp), Map.get(@half_bits, cp)} do
      {nil, nil} -> {scale_part(text, i, <<cp::utf8>>), seen}
      {nil, bits} -> half_cell(bits, c, div(i, g.cols), {fixed, g}, seen)
      {name, _} -> {name, seen}
    end
  end

  # A half block: the needle's if it shows pixels the dial does not draw.
  defp half_cell(bits, c, r, {fixed, %{cols: cols} = g}, seen) do
    top = c + 2 * r * cols
    bottom = top + cols
    k = bit(fixed, top) ||| bit(fixed, bottom) <<< 1

    case bits &&& bnot(k) do
      0 ->
        {fixed_part(c, r, Enum.filter([top, bottom], &MapSet.member?(fixed, &1)), g), seen}

      extra ->
        seen = if (extra &&& 1) != 0, do: [{c, 2 * r} | seen], else: seen
        seen = if (extra &&& 2) != 0, do: [{c, 2 * r + 1} | seen], else: seen
        {"needle", seen}
    end
  end

  # Cell centres nearer the pivot than r - 10 pixels (6 at most) are the
  # hub's, then nearer than r - 4 a tick's, then the rim's.
  defp fixed_part(c, r, pixels, %{r: rim, cx: cx, cy: cy}) do
    d = :math.sqrt((c - cx) * (c - cx) + (cy - 2 * r - 0.5) * (cy - 2 * r - 0.5))

    cond do
      d < min(6, rim - 10) -> "needle.hub"
      d < rim - 4 -> {:tick, pixels}
      true -> "dial"
    end
  end

  # A dial row's runs, its ticks settled.
  defp cut(line, cells, named) do
    {runs, _} =
      cells
      |> Enum.map(fn
        {{:tick, pixels}, n} -> {Map.fetch!(named, pixels), n}
        cell -> cell
      end)
      |> Enum.chunk_by(&elem(&1, 0))
      |> Enum.map_reduce(0, fn [{name, _} | _] = chunk, at ->
        n = chunk |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        {{name, binary_part(line, at, n)}, at + n}
      end)

    runs
  end

  # Whether the needle covers a tick, by its pixels: the needle's angle lies
  # in every square of its pixels in view, as seen from the pivot. The
  # needle is drawn at both ends and the middle of that span, and where the
  # three agree, the tick goes with them; where they do not, it goes with
  # the angles across the span that draw the needle in view exactly as it
  # is, if they agree, and is in no part if not. A sweep of readings in the
  # tests holds this to the needle actually drawn.
  defp tick_parts([], _seen, _fixed, _g), do: %{}

  defp tick_parts(ticks, seen, fixed, %{r: rim} = g) do
    {lo, hi} =
      Enum.reduce(seen, {-10.0, 10.0}, fn {x, y}, {lo, hi} ->
        {a, b} = sight(x, y, g)
        {max(lo, a), min(hi, b)}
      end)

    # The needle's steps that can land on a tick, from 3.5 pixels inside the
    # ticks to its tip.
    near = (4 * rim - 46)..(4 * rim - 32)
    rough = for a <- [lo, (lo + hi) / 2, hi], do: needle_pixels(a, near, g)
    named = Map.new(ticks, &{&1, covered(rough, &1)})

    if Enum.any?(named, &(elem(&1, 1) == :unsure)) do
      shown = MapSet.new(seen, fn {x, y} -> x + y * g.cols end)

      fine =
        for s <- 1..@search,
            pixels = needle_pixels(lo + (hi - lo) * (s - 0.5) / @search, needle_steps(g), g),
            MapSet.equal?(MapSet.difference(pixels, fixed), shown),
            do: pixels

      Map.new(named, fn
        {pixels, :unsure} -> {pixels, sure(covered(fine, pixels))}
        known -> known
      end)
    else
      named
    end
  end

  defp sure(:unsure), do: nil
  defp sure(name), do: name

  defp covered(samples, pixels) do
    case Enum.uniq(for s <- samples, do: Enum.any?(pixels, &MapSet.member?(s, &1))) do
      [true] -> "needle"
      [false] -> "axis"
      _ -> :unsure
    end
  end

  # The angles a pixel's square spans from the pivot, the needle's way round
  # (from below the right to below the left).
  defp sight(x, y, %{cx: cx, cy: cy}) do
    for dx <- [-0.5, 0.5], dy <- [-0.5, 0.5] do
      a = :math.atan2(cy - (y + dy), x + dx - cx)
      if a < -:math.pi() / 2, do: a + 2 * :math.pi(), else: a
    end
    |> Enum.min_max()
  end

  # The needle's pixels at angle `a`, those of steps `js`, as frame/3 draws them.
  defp needle_pixels(a, js, %{cx: cx, cy: cy, cols: cols}) do
    cos = :math.cos(a)
    sin = :math.sin(a)

    MapSet.new(js, fn j ->
      r = 2 + j * 0.25
      JSMath.round(cx + r * cos) + JSMath.round(cy - r * sin) * cols
    end)
  end

  # The readout, centred: the reading given, or upstream's, found where it
  # stands; under it, where it leaves them, the ends of the scale.
  defp readout_parts(line, text, %{unit: unit} = options, %{cols: cols} = g) do
    chars = line |> Text.chars() |> List.to_tuple()
    tail = tail(unit)
    span = reading(options, tail, g) || find_reading(chars, tail, g)

    for c <- 0..(cols - 1) do
      ch = elem(chars, c)

      case readout_part(span, c, tail) do
        :out -> {scale_part(text, c + readout_row(g) * cols, ch), ch}
        name -> {name, ch}
      end
    end
    |> Parts.merge()
  end

  defp tail(unit),
    do: if(String.starts_with?(unit, ["%", "°"]) or unit == "", do: unit, else: " " <> unit)

  # A cell's part in the readout (the space before a unit in none), or :out.
  defp readout_part(nil, _c, _tail), do: :out
  defp readout_part({c0, d, _n}, c, _tail) when c >= c0 and c < c0 + d, do: "value"
  defp readout_part({c0, d, _n}, c, " " <> _) when c == c0 + d, do: nil
  defp readout_part({c0, _d, n}, c, _tail) when c >= c0 and c < c0 + n, do: "unit"
  defp readout_part(_span, _c, _tail), do: :out

  defp scale_part(text, i, ch), do: if(Map.get(text, i) == ch, do: "scale")

  # Where the reading given is: its start, its digits and its length.
  defp reading(%{value: nil}, _tail, _g), do: nil

  defp reading(%{value: v}, tail, %{cols: cols, cx: cx}) do
    shown = v |> JSMath.round() |> JSMath.to_string()
    n = (shown <> tail) |> Text.slice(0, cols) |> Text.length()
    {JSMath.round(cx + 0.5 - n / 2), min(Text.length(shown), n), n}
  end

  # Upstream's readings: the whole number and the unit after it, centred.
  defp find_reading(chars, tail, %{cx: cx}) do
    cols = tuple_size(chars)
    tail = Text.chars(tail)
    tl = length(tail)

    Enum.find_value(1..(cols - tl)//1, fn d ->
      n = d + tl
      c0 = JSMath.round(cx + 0.5 - n / 2)

      if c0 >= 0 and c0 + n <= cols and whole?(chars, c0, d) and
           Enum.all?(Enum.with_index(tail, c0 + d), fn {ch, c} -> elem(chars, c) == ch end) and
           not numeral?(chars, c0 - 1) and (tl > 0 or not numeral?(chars, c0 + n)),
         do: {c0, d, n}
    end)
  end

  defp whole?(chars, c0, d) do
    first = elem(chars, c0)

    (first in @digits or (first == "-" and d > 1)) and
      Enum.all?((c0 + 1)..(c0 + d - 1)//1, &(elem(chars, &1) in @digits))
  end

  defp numeral?(chars, c) when c >= 0 and c < tuple_size(chars),
    do: elem(chars, c) in ["-" | @digits]

  defp numeral?(_chars, _c), do: false

  # The label, centred on the row under the readout.
  defp label_parts(line, label, %{cols: cols, cx: cx}) do
    n = label |> Text.slice(0, cols) |> Text.length()
    c0 = JSMath.round(cx + 0.5 - n / 2)

    Parts.merge([
      {nil, Text.slice(line, 0, c0)},
      {"label", Text.slice(line, c0, c0 + n)},
      {nil, Text.slice(line, c0 + n)}
    ])
  end
end
