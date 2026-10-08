defmodule AsciiArt.Pieces.Gauge do
  @moduledoc """
  Semicircle dial, the needle overshoots each new reading.

  A semicircle dial in half-block pixels, a band filled up to the reading,
  and a needle that springs to each new value, overshoots, and settles.

  ## Options

  `label`, `unit`, `min` and `max` are upstream's. This port adds `value`, a
  reading in `min`..`max` units for a dashboard or a terminal UI: the needle
  springs to it, and to each new one taken up while playing
  (`AsciiArt.put_options/2`), from wherever it is. The readout shows the
  reading itself. Without one (`nil`, the default) the gauge plays
  upstream's readings.

  Ported from `src/pieces/gauge.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Text
  import Bitwise, only: [<<<: 2, >>>: 2, |||: 2, &&&: 2]

  @meta %AsciiArt.Meta{
    name: "gauge",
    category: :data,
    note: "semicircle dial, the needle overshoots each new reading",
    cols: 55,
    rows: 18,
    fps: 30,
    options: %{label: "load", unit: "%", min: 0, max: 100, value: nil}
  }

  # Seconds per reading; damping (about a quarter overshoot); natural
  # frequency in rad/s.
  @hold 2.6
  @zeta 0.38
  @w0 5.2
  @half {" ", "▀", "▄", "█"}
  # Rim radius in pixels; a pixel is a cell wide and half a cell tall.
  @r 22
  # The pivot pixel.
  @cx 27
  @cy 27
  @h 18 * 2

  @impl true
  def meta, do: @meta

  defp angle_of(v), do: :math.pi() * (1 - v / 100)

  defp plot(set, x, y) do
    c = JSMath.round(x)
    r = JSMath.round(y)

    if c >= 0 and c < @meta.cols and r >= 0 and r < @h,
      do: MapSet.put(set, c + r * @meta.cols),
      else: set
  end

  @impl true
  def init(%{label: label, unit: unit, min: lo, max: hi} = options) do
    %{cols: cols, rows: rows} = @meta
    text = numbers(lo, hi)
    fixed = fixed()

    # Pixels that never move, by cell: the top pixel is bit 1, the bottom bit 2.
    k_of = fn c, r ->
      y = 2 * r
      bit(fixed, c + y * cols) ||| bit(fixed, c + (y + 1) * cols) <<< 1
    end

    # A dot between ticks.
    dots =
      for v <- 5..95//10, into: %{} do
        a = angle_of(v)

        {JSMath.round(@cx + (@r - 7.5) * :math.cos(a)) +
           JSMath.floor((@cy - (@r - 7.5) * :math.sin(a) + 0.5) / 2) * cols, "·"}
      end

    cells =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          i = c + r * cols
          {Map.get(text, i), k_of.(c, r), Map.get(dots, i), band(c, r)}
        end
      end

    a = @zeta * @w0
    w = @w0 * :math.sqrt(1 - @zeta * @zeta)

    readings =
      extend(%{targets: %{0 => 55}, states: %{0 => {30, 0}}, n: 1, rand: 42, a: a, w: w}, 4)

    %{
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
  defp fixed do
    set =
      Enum.reduce(-@r..@r, MapSet.new(), fn x, set ->
        plot(set, @cx + x, @cy - :math.sqrt(@r * @r - x * x))
      end)

    set =
      Enum.reduce(0..@r, set, fn y, set ->
        x = :math.sqrt(@r * @r - y * y)
        set |> plot(@cx - x, @cy - y) |> plot(@cx + x, @cy - y)
      end)

    set =
      for v <- 0..100//10, r <- [@r - 8, @r - 7], reduce: set do
        set ->
          a = angle_of(v)
          plot(set, @cx + r * :math.cos(a), @cy - r * :math.sin(a))
      end

    for y <- -2..2, x <- -2..2, x * x + y * y <= 5, reduce: set do
      set -> plot(set, @cx + x, @cy + y)
    end
  end

  # The band's cells by angle (upstream's NaN, outside the band, is nil),
  # stored in a Float32Array.
  defp band(c, r) do
    dx = c - @cx
    dy = @cy - (2 * r + 0.5)
    d = JSMath.hypot(dx, dy)

    if dy > -0.6 and d > @r - 4.1 and d < @r - 2.1,
      do: JSMath.fround(:math.atan2(max(0, dy), dx))
  end

  # Numbers every 20 just outside the rim; the two ends sit under it.
  defp numbers(lo, hi) do
    cols = @meta.cols

    for v <- 0..100//20, reduce: %{} do
      text ->
        a = angle_of(v)
        s = JSMath.to_string(JSMath.round(lo + (hi - lo) * v / 100))
        n = Text.length(s)
        side? = rem(v, 100) != 0
        rr = if side?, do: @r + 2.5, else: @r
        x = @cx + rr * :math.cos(a) + if(side?, do: n / 2 * :math.cos(a), else: 0)
        y = if side?, do: @cy - (rr + 1) * :math.sin(a), else: @cy + 3
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
  def frame(state, t, _env) do
    %{cols: cols} = @meta
    %{lo: lo, hi: hi} = state
    {v, state} = needle(state, t)
    v = max(-1, min(101, v))
    an = angle_of(v)
    cos = :math.cos(an)
    sin = :math.sin(an)

    needle =
      Enum.reduce(0..56, %{}, fn j, needle ->
        r = 2 + j * 0.25
        x = JSMath.round(@cx + r * cos)
        y = JSMath.round(@cy - r * sin)

        if x >= 0 and x < cols and y >= 0 and y < @h,
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
      |> centre(JSMath.to_string(shown) <> tail, (@cy >>> 1) + 2)
      |> centre(state.label, (@cy >>> 1) + 3)

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

  defp centre(overlay, s, r) do
    cols = @meta.cols
    s = Text.slice(s, 0, cols)
    c0 = JSMath.round(@cx + 0.5 - Text.length(s) / 2)

    s
    |> Text.chars()
    |> Enum.with_index(c0)
    |> Enum.reduce(overlay, fn {ch, c}, overlay ->
      if c >= 0 and c < cols, do: Map.put(overlay, c + r * cols, ch), else: overlay
    end)
  end
end
