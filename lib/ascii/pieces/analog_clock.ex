defmodule Ascii.Pieces.AnalogClock do
  @moduledoc """
  A round clock face showing the local time, seconds ticking.

  A round wall clock keeping local time. A lit bezel, a tick for every minute
  and hour, and hour, minute and ticking second hands.

  Reads the clock from `env.now` (see `Ascii.Kit.Clock`). Upstream notes
  the wall clock when the piece is made; this port notes it at the first
  frame, which is the same moment when a piece is played as soon as it is
  made.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them, at the time it reads.

    * `seconds` - the second hand: a fine line with a ring at its tip and a
      weight on its tail, ticking once a second. Default `true`; `false`
      leaves the hour and minute hands.
    * `numerals` - 12, 3, 6 and 9 at the quarters, in place of their ticks.
      Default `true`; `false` puts a tick at every hour.

  The picture is always 47 by 23. Like any piece that reads the clock, it
  takes `now:` in `Ascii.frame/3` to draw a given moment.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `Ascii.Ink`),
  or on a page a CSS variable. On a light page, give it `paper: true`: its
  shading reads from the other end of its ramp, so dense characters still mean
  dark. It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "analog clock: a round clock
  face showing the local time, seconds ticking". A player's or a component's
  `label` gives words of your own, as "the time".

  ## Example

  ```elixir
  now = DateTime.new!(~D[2026-03-14], ~T[15:09:26], "Etc/UTC")
  plain = Ascii.new!("analog-clock", options: %{numerals: false, seconds: false})
  {frame, _} = Ascii.frame(plain, 0.0, now: now)
  {frame.cols, frame.rows, frame.text =~ "12"}
  #=> {47, 23, false}
  ```

  ```heex
  <Ascii.Phoenix.player socket={@socket} id="clock" piece="analog-clock" options={%{numerals: false}} label="the time" />
  ```

  Ported from `src/pieces/analog-clock.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Clock, Grid}

  @meta %Ascii.Meta{
    name: "analog clock",
    category: :objects,
    note: "a round clock face showing the local time, seconds ticking",
    cols: 47,
    rows: 23,
    fps: 8,
    options: %{numerals: true, seconds: true},
    clock: true
  }

  @ramp {".", ",", "-", "~", ":", ";", "=", "!", "*", "#", "$", "@"}
  # The stretch of the ramp the bezel uses, so no part of it fades out.
  @lo 3
  @hi 10
  # The bezel's middle, in columns; the face is drawn in columns, y up.
  @r 21

  @cx 47 / 2
  @cy 23 / 2

  # How each hand is drawn: upright, rising and falling strokes, the run along
  # a row where it is shallow, the run where it lies flat in one row, and how
  # many columns a row it may cross before it is drawn as runs.
  @hour %{up: "║", rise: "/", fall: "\\", run: "=", flat: "=", wide: true, span: 2.4}
  @minute %{up: "|", rise: "/", fall: "\\", run: "_", flat: "-", wide: false, span: 1.3}
  @second %{up: "│", rise: "╱", fall: "╲", run: "─", flat: "─", wide: false, span: 1.3}

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{numerals: numerals, seconds: seconds}) do
    %{numerals: numerals, seconds: seconds, start: nil, bezel: {bezel(false), bezel(true)}}
  end

  # The bezel is a fixed picture: a torus cut across, lit from the upper left,
  # sampled four times a cell. Shading only depends on paper, so keep both.
  defp bezel(paper) do
    %{cols: cols, rows: rows} = @meta
    lm = JSMath.hypot(-0.5, 0.6, 0.62)
    {lx, ly, lz} = {-0.5 / lm, 0.6 / lm, 0.62 / lm}
    last = tuple_size(@ramp) - 1

    for r <- 0..(rows - 1), c <- 0..(cols - 1), reduce: Grid.new(cols, rows) do
      grid ->
        {sum, hit} =
          for {ox, oy} <- [{0.25, 0.25}, {0.75, 0.25}, {0.25, 0.75}, {0.75, 0.75}],
              reduce: {0, 0} do
            {sum, hit} ->
              x = c + ox - @cx
              y = (@cy - (r + oy)) * 2
              d = JSMath.hypot(x, y)
              s = (d - @r) / 1.3

              if abs(s) >= 1 do
                {sum, hit}
              else
                z = :math.sqrt(1 - s * s)
                {sum + max(0, s * x / d * lx + s * y / d * ly + z * lz), hit + 1}
              end
          end

        if hit < 2 do
          grid
        else
          i = JSMath.round(@lo + sum / hit * (@hi - @lo))
          Grid.put(grid, c, r, elem(@ramp, if(paper, do: last - i, else: i)))
        end
    end
  end

  @impl true
  def frame(state, t, env) do
    # The wall clock, or play time from the start if that is ahead of it.
    wall = Clock.now_ms(env)
    start = state.start || wall
    now = Clock.local(env, max(wall, start + t * 1000))
    sec = now.second
    min = now.minute + sec / 60
    hr = rem(now.hour, 12) + min / 60
    grid = elem(state.bezel, if(env.paper, do: 1, else: 0))

    # A dot for each minute and a one-cell stroke for each hour.
    grid =
      Enum.reduce(0..59, grid, fn i, g ->
        a = i * :math.pi() / 30
        sx = :math.sin(a)
        sy = :math.cos(a)

        cond do
          rem(i, 5) != 0 ->
            put(g, sx * 18, sy * 18, "·")

          not state.numerals or rem(i, 15) != 0 ->
            ch =
              cond do
                abs(sy) > 0.9 -> "|"
                abs(sy) < 0.1 -> "-"
                sx * sy > 0 -> "/"
                true -> "\\"
              end

            put(g, sx * 17.4, sy * 17.4, ch)

          true ->
            g
        end
      end)

    ah = hr * :math.pi() / 6
    am = min * :math.pi() / 30
    as = sec * :math.pi() / 30
    {grid, _} = hand(grid, ah, 1.5, 9.5, @hour)
    {grid, _} = hand(grid, am, 1.5, 15.5, @minute)

    # The second hand: a fine line with a ring at its tip and a weight on its
    # tail, a half block in whichever half of its cell the tail ends.
    {grid, tip} =
      if state.seconds do
        {grid, tip} = hand(grid, as, 1.5, 14.8, @second)
        {grid, w} = hand(grid, as + :math.pi(), 1.5, 4.4, @second)
        f = @cy + :math.cos(as) * 2.2

        case w do
          {c, r} -> {Grid.put(grid, c, r, if(f - floor(f) < 0.5, do: "▀", else: "▄")), tip}
          nil -> {grid, tip}
        end
      else
        {grid, nil}
      end

    # The numerals sit over the hour and minute hands; the ring passes over them.
    grid =
      if state.numerals do
        grid
        |> put(-1, 15.6, "1")
        |> put(0, 15.6, "2")
        |> put(15.2, 0, "3")
        |> put(0, -15.6, "6")
        |> put(-15.2, 0, "9")
      else
        grid
      end

    grid =
      case tip do
        {c, r} -> Grid.put(grid, c, r, "o")
        nil -> grid
      end

    grid = put(grid, 0, 0, "@")
    {Grid.to_iodata(grid), nil, %{state | start: start}}
  end

  defp put(grid, x, y, ch), do: Grid.put(grid, floor(@cx + x), floor(@cy - y / 2), ch)

  # A hand along clock angle a (radians from twelve, clockwise) from r0 to r1
  # columns out, taken a row at a time. Steep, it is one stroke a row;
  # shallow, a run along the row stepped up or down where it crosses into the
  # next. Returns the cell it ends in.
  defp hand(grid, a, r0, r1, st) do
    sx = :math.sin(a)
    sy = :math.cos(a)

    hand = %{
      sx: sx,
      sy: sy,
      r0: r0,
      r1: r1,
      st: st,
      # Within about 14 degrees of upright.
      steep: abs(sy) > 4 * abs(sx),
      rise: sx * sy > 0,
      # Columns crossed in a full row.
      runs: 2 * abs(sx) > st.span * abs(sy)
    }

    ya = y_at(hand, r0)
    yb = y_at(hand, r1)

    Enum.reduce(floor(min(ya, yb))..floor(max(ya, yb))//1, {grid, nil}, fn r, acc ->
      hand_row(hand, r, acc)
    end)
  end

  defp y_at(hand, s), do: @cy - hand.sy * s / 2
  defp x_at(hand, s), do: @cx + hand.sx * s

  defp hand_row(%{sy: sy, r0: r0, r1: r1} = hand, r, acc) do
    if abs(sy) > 1.0e-6 do
      p = (@cy - r) * 2 / sy
      q = (@cy - r - 1) * 2 / sy
      s0 = max(r0, min(p, q))
      s1 = min(r1, max(p, q))
      if s1 - s0 < 1.0e-6, do: acc, else: hand_span(hand, r, s0, s1, acc)
    else
      hand_span(hand, r, r0, r1, acc)
    end
  end

  defp hand_span(%{st: st, r1: r1, rise: rise} = hand, r, s0, s1, acc) do
    xa = x_at(hand, s0)
    xb = x_at(hand, s1)

    span = %{
      xa: xa,
      xb: xb,
      lo: min(xa, xb),
      hi: max(xa, xb),
      last: s1 > r1 - 1.0e-6,
      s0: s0,
      s1: s1
    }

    slant = if rise, do: st.rise, else: st.fall
    if hand.runs, do: hand_run(hand, r, span, acc), else: hand_stroke(hand, r, span, slant, acc)
  end

  # Steep: one stroke a row (two for the wide hour hand).
  defp hand_stroke(
         %{st: st, steep: steep},
         r,
         %{lo: lo, hi: hi, last: last},
         slant,
         {grid, ending}
       ) do
    mid = (lo + hi) / 2
    c = floor(mid)
    grid = Grid.put(grid, c, r, if(steep, do: st.up, else: slant))

    grid =
      if st.wide and not steep,
        do: Grid.put(grid, if(mid - c < 0.5, do: c - 1, else: c + 1), r, slant),
        else: grid

    {grid, if(last, do: {c, r}, else: ending)}
  end

  # Shallow: a run along the row.
  defp hand_run(%{st: st, r0: r0, r1: r1, rise: rise} = hand, r, span, {grid, ending}) do
    %{xa: xa, xb: xb, lo: lo, hi: hi, last: last, s0: s0, s1: s1} = span
    # Which ends of this row's run meet the row above or below.
    {s_lo, s_hi} = if xa < xb, do: {s0, s1}, else: {s1, s0}
    edge_lo = s_lo > r0 + 1.0e-6 and s_lo < r1 - 1.0e-6
    edge_hi = s_hi > r0 + 1.0e-6 and s_hi < r1 - 1.0e-6
    ch = if edge_lo or edge_hi, do: st.run, else: st.flat
    c0 = floor(lo)
    c1 = floor(hi - 1.0e-6)
    grid = Enum.reduce(c0..c1//1, grid, &Grid.put(&2, &1, r, ch))
    ending = if last, do: {max(c0, min(c1, floor(x_at(hand, r1)))), r}, else: ending

    cond do
      st.wide -> {grid, ending}
      rise and edge_hi -> {Grid.put(grid, c1, r, st.rise), ending}
      not rise and edge_lo -> {Grid.put(grid, c0, r, st.fall), ending}
      true -> {grid, ending}
    end
  end
end
