defmodule AsciiArt.Pieces.Equalizer do
  @moduledoc """
  Spectrum bars bouncing to a beat, peak caps falling slowly.

  A spectrum analyser over a short drum and bass loop. Bars jump to each
  band's level and sink back, and peak caps hold, then drop slowly.

  ## Options

  `bpm` is upstream's. This port adds `levels`, for real audio: each band's
  level from 0 to 1, low to high, spread over the nineteen bars whatever
  their number. The bars jump to them and sink back, the caps hold and
  drop, as they do to the loop; take new levels up as they come
  (`AsciiArt.put_options/2`) and the bars carry on from where they were.

  Ported from `src/pieces/equalizer.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Grid
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "equalizer",
    category: :data,
    note: "spectrum bars bouncing to a beat, peak caps falling slowly",
    cols: 62,
    rows: 16,
    fps: 30,
    options: %{bpm: 120, levels: []},
    bounds: %{bpm: {60, 180}},
    shapes: %{levels: [0.0]}
  }

  # Half octaves from 31 Hz to 16 kHz.
  @bands 19
  @labels ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
  # Plot height in rows.
  @ph 12
  @eighths {"▁", "▂", "▃", "▄", "▅", "▆", "▇"}
  # Bar fall, heights per second; seconds a peak cap waits before it drops;
  # how fast a dropping cap speeds up.
  @fall 2.2
  @hold 0.5
  @gravity 1.1
  @kick_gain 1.4
  @bass_gain 0.34
  @snare_gain 0.95
  @hat_gain 0.75
  @chord_gain 0.15
  @knee 1.4
  # The loudest a band reaches, so caps always show.
  @headroom 0.95

  # Sixteen steps a bar. The loop is four bars, the last with a fill.
  @kick ["x.....x.x...x...", "x.....x.x.....x.", "x.....x.x...x...", "x.....x.x.x.x.xx"]
  @snare ["....x.......x...", "....x.......x..x", "....x.......x...", "....x..x..x.xxxx"]
  @hat ["x.x.x.xxx.x.x.xx"]
  # Band per beat.
  @bass {0, 0, 2, 3, 1, 1, 3, 2, 0, 0, 2, 4, 3, 2, 1, 0}
  @chords [[8, 10, 13], [7, 10, 12], [9, 11, 13], [8, 11, 14]]

  # The axis row.
  @ay 1 + @ph

  @compile {:inline, hash: 1, umul: 2}

  @impl true
  def meta, do: @meta

  # New levels: the bars and caps carry on from where they were.
  @impl true
  def update(state, options), do: %{init(options) | sim: state.sim}

  @impl true
  def init(%{bpm: bpm} = options) do
    %{cols: cols, rows: rows} = @meta
    # Seconds per sixteenth.
    step = 15 / max(60, min(180, bpm))
    x0 = JSMath.floor((cols - (@bands * 3 - 1)) / 2)

    base =
      Enum.reduce(
        (x0 - 1)..(x0 + @bands * 3 - 1),
        Grid.new(cols, rows),
        &Grid.put(&2, &1, @ay, "─")
      )

    base =
      @labels
      |> Enum.with_index()
      |> Enum.reduce(base, fn {s, i}, g ->
        Grid.put_string(g, x0 + i * 6 + 1 - JSMath.floor(String.length(s) / 2), @ay + 1, s)
      end)

    model = %{
      levels: levels(options.levels),
      step: step,
      kick: pattern(@kick),
      snare: pattern(@snare),
      hat: pattern(@hat),
      statics: statics()
    }

    # Play a few bars in so frame 0 is mid song, just after a kick, then count
    # time from there.
    warm = step * (16 * 3 + 6) + 0.04
    zero = {0.0, 0.0, 0.0, 0.0}
    fresh = %{last: 0, bands: List.duplicate(zero, @bands)}
    sim = Enum.reduce(0..90, fresh, fn i, sim -> advance(sim, warm * i / 90, model) end)

    %{model: model, warm: warm, x0: x0, base: base, start: sim, sim: sim}
  end

  # The levels given, one a bar: band b takes the level its place among them
  # falls on.
  defp levels([]), do: nil

  defp levels(levels) do
    given = List.to_tuple(levels)
    n = tuple_size(given)
    for b <- 0..(@bands - 1), do: given |> elem(div(b * n, @bands)) |> max(0) |> min(1)
  end

  defp pattern(bars),
    do: bars |> Enum.map(&(&1 |> String.to_charlist() |> List.to_tuple())) |> List.to_tuple()

  # Each band's weights that never change: the kick, snare and hat curves, the
  # bass note's curve for each note, and the chord tones' for each chord.
  defp statics do
    for b <- 0..(@bands - 1) do
      bass =
        for note <- 0..4 do
          bass = note + 0.6
          :math.exp(-sq((b - bass) / 0.9)) + 0.5 * :math.exp(-sq((b - bass - 2) / 1.1))
        end

      chords =
        for chord <- @chords do
          for c <- chord, do: :math.exp(-sq(b - c)) + 0.5 * :math.exp(-sq(b - c - 2))
        end

      {b, :math.exp(-sq((b - 1.2) / 1.4)), :math.exp(-sq((b - 9) / 4.2)),
       :math.exp(-sq((b - 16) / 2.2)), List.to_tuple(bass), List.to_tuple(chords)}
    end
  end

  defp sq(x), do: x * x

  defp umul(a, b), do: Int32.umul(a, b)

  defp hash(n) do
    n = Int32.u32(n)
    n = umul(bxor(n, n >>> 16), 0x7FEB352D)
    n = umul(bxor(n, n >>> 15), 0x846CA68B)
    bxor(n, n >>> 16) / 4_294_967_296
  end

  # Time since the last hit of a pattern, looking back up to a bar.
  defp since(t, step, pat) do
    s = JSMath.floor(t / step)

    Enum.find_value(0..15, 9, fn k ->
      j = s - k
      p = elem(pat, rem(Integer.mod(Integer.floor_div(j, 16), 4), tuple_size(pat)))
      if elem(p, Integer.mod(j, 16)) == ?x, do: t - j * step
    end)
  end

  defp spectrum(_t, %{levels: levels}) when levels != nil, do: Enum.map(levels, &JSMath.fround/1)

  defp spectrum(t, %{step: step} = model) do
    kick = :math.exp(-since(t, step, model.kick) / 0.14)
    snare = :math.exp(-since(t, step, model.snare) / 0.11)
    hat = :math.exp(-since(t, step, model.hat) / 0.045)
    beat = JSMath.floor(t / (step * 4))
    beat_frac = t / (step * 4) - beat
    bass = elem(@bass, Integer.mod(beat, 16))
    chord = Integer.mod(Integer.floor_div(beat, 4), 4)
    # The chord ducks under each beat and swells back, as if sidechained.
    pump = 0.5 + 0.5 * (1 - :math.exp(-beat_frac * 4))
    kick_amp = @kick_gain * kick
    bass_amp = @bass_gain * (0.45 + 0.55 * :math.exp(-beat_frac * 3))
    hat_amp = @hat_gain * hat
    chord_amp = @chord_gain * pump
    # Smooth flutter per band, a pure function of time.
    x = t * 9
    i = JSMath.floor(x)
    f = x - i
    u = f * f * (3 - 2 * f)

    for {b, kw, sw, hw, bws, cws} <- model.statics do
      n = hash(b * 7919 + i) * (1 - u) + hash(b * 7919 + i + 1) * u

      sum =
        0.03 + 0.08 * n - 0.001 * b + kick_amp * kw + bass_amp * elem(bws, bass) +
          @snare_gain * (0.75 + 0.25 * n) * snare * sw + hat_amp * hw * (0.6 + 0.4 * n)

      # The chord rings in the mids, each tone with a weaker overtone.
      g = chord_amp * (0.7 + 0.3 * n)
      sum = Enum.reduce(elem(cws, chord), sum, &(&2 + g * &1))
      # A soft knee, so loud bands still move instead of pinning at the top.
      JSMath.fround(@headroom * (1 - :math.exp(-@knee * sum)))
    end
  end

  defp advance(%{last: last, bands: bands}, t, model) do
    dt = min(0.1, max(0, t - last))

    bands =
      Enum.zip_with(spectrum(t, model), bands, fn level, {bar, peak, vel, held} ->
        bar = JSMath.fround(max(level, bar - @fall * dt))

        if bar >= peak do
          {bar, bar, 0.0, @hold}
        else
          # The test reads the difference itself, before the Float32Array rounds it.
          h = held - dt

          if h < 0 do
            vel = JSMath.fround(vel + @gravity * dt)
            {bar, JSMath.fround(max(bar, peak - vel * dt)), vel, JSMath.fround(h)}
          else
            {bar, peak, vel, JSMath.fround(h)}
          end
        end
      end)

    %{last: t, bands: bands}
  end

  @impl true
  def frame(%{model: model, warm: warm} = state, t, _env) do
    # Upstream starts over from the warm-up when time goes back past it.
    sim = if t + warm < state.sim.last, do: state.start, else: state.sim
    sim = advance(sim, t + warm, model)

    grid =
      sim.bands
      |> Enum.with_index()
      |> Enum.reduce(state.base, fn {{bar, peak, _, _}, b}, g ->
        draw(g, state.x0 + b * 3, bar, peak)
      end)

    {Grid.to_iodata(grid), nil, %{state | sim: sim}}
  end

  defp draw(g, x, bar, peak) do
    h = JSMath.round(min(1, bar) * @ph * 8)
    full = h >>> 3
    part = h &&& 7
    g = Enum.reduce(0..(full - 1)//1, g, &pair(&2, x, @ay - 1 - &1, "█"))
    g = if part != 0, do: pair(g, x, @ay - 1 - full, elem(@eighths, part - 1)), else: g
    # The cap is one thin line, drawn once a clear cell parts it from the bar.
    pr = min(@ph * 8 - 1, JSMath.round(min(1, peak) * @ph * 8)) >>> 3

    if pr >= if(part != 0, do: full, else: full - 1) + 2,
      do: pair(g, x, @ay - 1 - pr, "▁"),
      else: g
  end

  defp pair(g, x, r, ch), do: g |> Grid.put(x, r, ch) |> Grid.put(x + 1, r, ch)
end
