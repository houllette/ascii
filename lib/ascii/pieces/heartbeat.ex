defmodule Ascii.Pieces.Heartbeat do
  @moduledoc """
  An ecg trace sweeping over its last pass, with a bpm readout.

  An ECG monitor. A PQRST trace sweeps left to right over a dotted grid and
  its last pass, erasing a few columns ahead, beside a rate readout.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): the
  monitor starts afresh at the new rate.

    * `bpm` - the heart rate, beats a minute, 30 to 199: the trace's pace,
      and the readout in large digits. Default 72.

  The frame is always 72 by 15.

  ## Colours

  It has no parts to colour one by one: in one ink, or a gradient, with
  `:ink` and `:gradient` (see `Ascii.Ink`). A green ink makes the
  monitor's own.

  ## Keys and clicks

  It takes none: it shows a rate, and `Ascii.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still tells
  your LiveView where it was clicked.

  ## Screen readers

  `Ascii.describe/1` reads the rate, as the readout shows it: "heartbeat:
  72 bpm".

  ## Example

  ```elixir
  monitor = Ascii.new!("heartbeat", options: %{bpm: 90}, ink: "#3fb950")

  Ascii.describe(monitor)
  #=> "heartbeat: 90 bpm"

  {frame, _monitor} = Ascii.frame(monitor, 1.0)
  {frame.cols, frame.rows, frame.palette}
  #=> {72, 15, ["#3fb950"]}
  ```

  ```heex
  <Ascii.Phoenix.live_player id="pulse" piece="heartbeat" options={%{bpm: @bpm}} ink="#3fb950" />
  ```

  Ported from `src/pieces/heartbeat.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}
  alias Ascii.Kit.{Grid, Text}
  import Bitwise, only: [>>>: 2]

  @meta %Ascii.Meta{
    name: "heartbeat",
    category: :data,
    note: "an ecg trace sweeping over its last pass, with a bpm readout",
    cols: 72,
    rows: 15,
    fps: 25,
    options: %{bpm: 72},
    bounds: %{bpm: {30, 199}}
  }

  # Columns per second, like 25 mm/s paper; trace width; erased columns ahead
  # of the trace; baseline row.
  @speed 25
  @w 46
  @gap 4
  @base 10
  # One beat as rows above the baseline at each column edge: P, PR, QRS, ST, T.
  @beat {0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 1, 0}
  # The QRS is drawn by hand, a column each: Q dips a row, R rises from that
  # dip to a point, and S climbs back to the baseline.
  @r_at 7
  @r_top 7
  @qrs %{(@r_at - 1) => {"╮", "╰"}, (@r_at + 1) => {"╭", "╯"}}

  # Digits for the readout, 3x5, each pixel two columns wide and a row tall.
  @font [
          "###,#.#,#.#,#.#,###",
          "##.,.#.,.#.,.#.,###",
          "###,..#,###,#..,###",
          "###,..#,###,..#,###",
          "#.#,#.#,###,..#,..#",
          "###,#..,###,..#,###",
          "###,#..,###,#.#,###",
          "###,..#,..#,..#,..#",
          "###,#.#,###,#.#,###",
          "###,#.#,###,..#,###"
        ]
        |> Enum.map(fn d ->
          for {line, r} <- d |> String.split(",") |> Enum.with_index(),
              {?#, c} <- line |> String.to_charlist() |> Enum.with_index(),
              do: {r, c}
        end)
        |> List.to_tuple()

  # The heart swells on each beat, eases back and rests smaller between.
  @hearts {
    [" ▄█▄█▄ ", "  ▀█▀  ", "       "],
    ["▄██▄██▄", " ▀███▀ ", "   ▀   "],
    ["▄██▄██▄", "▀█████▀", "  ▀█▀  "]
  }

  # First trace column, the readout panel and its width.
  @x0 2
  @px @x0 + @w + 3
  @pw @meta.cols - @px - 1

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{bpm: bpm}) do
    %{cols: cols, rows: rows} = @meta
    base = cols |> Grid.new(rows) |> Grid.put_string(@x0, 1, "ecg  ii")
    base = Grid.put_string(base, @x0 + @w - 7, 1, "25 mm/s")
    base = Enum.reduce(1..(rows - 2), base, &Grid.put(&2, @px - 2, &1, "│"))
    base = base |> Grid.put_string(@px, 2, "hr") |> Grid.put_string(@px + @pw - 3, 2, "bpm")

    # Beat start times in columns, made as far as needed, left fractional so
    # the rate averages true. Breathing sways it a little.
    %{base: base, rate: max(30, min(199, bpm)), beats: {-400}, rand: 7240}
  end

  # The rate it beats at; the readout wanders a little about it, as a
  # monitor's does.
  @impl true
  def describe(%{bpm: bpm}),
    do: "heartbeat: #{bpm |> max(30) |> min(199) |> JSMath.round() |> JSMath.to_string()} bpm"

  defp extend(%{beats: beats} = state, g) do
    n = tuple_size(beats)
    last = elem(beats, n - 1)

    if last <= g do
      {x, rand} = Int32.mulberry32(state.rand)
      rate = state.rate + 2.5 * :math.sin(n * 0.8) + (x - 0.5) * 2

      extend(
        %{state | beats: :erlang.append_element(beats, last + @speed * 60 / rate), rand: rand},
        g
      )
    else
      state
    end
  end

  defp beat_of(beats, g), do: search(beats, g, 0, tuple_size(beats) - 1)

  defp search(_beats, _g, lo, hi) when lo >= hi, do: lo

  defp search(beats, g, lo, hi) do
    mid = (lo + hi + 1) >>> 1
    if elem(beats, mid) <= g, do: search(beats, g, mid, hi), else: search(beats, g, lo, mid - 1)
  end

  # A sample's column in the beat. Beats too close for the whole beat take
  # up to two columns each out of the flat PR and ST stretches.
  defp start(beats, n), do: JSMath.ceil(elem(beats, n))

  defp cut(beats, n),
    do: max(0, min(4, tuple_size(@beat) - (start(beats, n + 1) - start(beats, n))))

  # Before the first beat there is none: upstream's NaN, which reads as level 0.
  defp phase(_beats, n, _g) when n < 0, do: nil

  defp phase(beats, n, g) do
    c = cut(beats, n)
    pr = (c + 1) >>> 1
    k = g - start(beats, n)
    k = if k >= @r_at - 1 - pr, do: k + pr, else: k
    if k >= 12 - (c - pr), do: k + (c - pr), else: k
  end

  defp beat_at(k) when is_integer(k) and k >= 0 and k < tuple_size(@beat), do: elem(@beat, k)
  defp beat_at(_k), do: 0

  # Faster still, a beat's T wave runs on under the next one's P.
  defp level(beats, g) do
    n = beat_of(beats, g)
    max(beat_at(phase(beats, n, g)), beat_at(phase(beats, n - 1, g)))
  end

  defp r_at(beats, n), do: start(beats, n) + @r_at - ((cut(beats, n) + 1) >>> 1)

  @impl true
  def frame(state, t, _env) do
    # The newest sample.
    h = 3 * @w + 31 + JSMath.floor(t * @speed)
    state = extend(state, h + 2)
    beats = state.beats
    head = rem(h, @w)

    grid =
      Enum.reduce(0..(@w - 1), state.base, fn c, grid ->
        ahead = rem(c - head + @w, @w)

        if ahead > 0 and ahead <= @gap,
          do: grid,
          else: column(grid, beats, c, h - rem(head - c + @w, @w))
      end)

    # The rate averages the last four beats that have shown their R wave.
    n = beat_of(beats, h - @r_at + 2)
    n = if r_at(beats, n) > h, do: n - 1, else: n
    rr = (elem(beats, n) - elem(beats, n - 4)) / 4
    shown = JSMath.to_string(JSMath.round(@speed * 60 / rr))
    grid = digits(grid, shown)
    since = h - r_at(beats, n)
    heart = elem(@hearts, if(since < 4, do: 2, else: if(since < 9, do: 1, else: 0)))

    grid =
      heart
      |> Enum.with_index()
      |> Enum.reduce(grid, fn {s, i}, grid ->
        Grid.put_string(grid, @px + JSMath.floor((@pw - 7) / 2), 10 + i, s)
      end)

    {Grid.to_iodata(grid), nil, state}
  end

  defp column(grid, beats, c, g) do
    x = @x0 + c
    rows = @meta.rows

    # A dot every five columns on every third row, under the trace and clear
    # of the baseline.
    grid =
      if rem(c, 5) == 2,
        do:
          Enum.reduce(
            (@base - 6)..(rows - 2)//3,
            grid,
            &if(&1 != @base, do: Grid.put(&2, x, &1, "·"), else: &2)
          ),
        else: grid

    k = phase(beats, beat_of(beats, g), g)

    cond do
      k == @r_at ->
        grid = Grid.put(grid, x, @base - @r_top, "╷")
        grid = Enum.reduce((@base - @r_top + 1)..@base, grid, &Grid.put(&2, x, &1, "│"))
        Grid.put(grid, x, @base + 1, "┴")

      Map.has_key?(@qrs, k) ->
        {above, below} = @qrs[k]
        grid |> Grid.put(x, @base, above) |> Grid.put(x, @base + 1, below)

      true ->
        # Elsewhere each column carries the line from this sample to the next.
        a = @base - level(beats, g)
        b = @base - level(beats, g + 1)
        top = min(a, b)
        bot = max(a, b)

        Enum.reduce(
          top..bot,
          grid,
          &Grid.put(&2, x, &1, join(&1 > top, &1 < bot, &1 == a, &1 == b))
        )
    end
  end

  # A cell's glyph from the sides its line leaves by: up, down, left, right.
  defp join(true, true, false, false), do: "│"
  defp join(false, false, true, true), do: "─"
  defp join(false, true, true, false), do: "╮"
  defp join(true, false, true, false), do: "╯"
  defp join(false, true, false, true), do: "╭"
  defp join(true, false, false, true), do: "╰"
  defp join(_up, _down, _left, _right), do: "─"

  defp digits(grid, shown) do
    n = Text.length(shown)
    step = if n > 2, do: 7, else: 8
    dx = @px + JSMath.floor((@pw - n * step + step - 6) / 2)

    {grid, _} =
      shown
      |> String.to_charlist()
      |> Enum.reduce({grid, dx}, fn ch, {grid, dx} ->
        grid =
          @font
          |> elem(ch - ?0)
          |> Enum.reduce(grid, fn {r, c}, grid ->
            grid |> Grid.put(dx + 2 * c, 4 + r, "█") |> Grid.put(dx + 2 * c + 1, 4 + r, "█")
          end)

        {grid, dx + step}
      end)

    grid
  end
end
