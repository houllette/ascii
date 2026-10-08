defmodule AsciiArt.Pieces.DigitalClock do
  @moduledoc """
  The local time in seven-segment digits, colon blinking.

  The local time as big seven-segment digits, HH:MM:SS, with the colon
  blinking each second and the date set small underneath.

  Reads the clock from `env.now` (see `AsciiArt.Kit.Clock`).

  Ported from `src/pieces/digital-clock.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.{Clock, Grid, Text}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "digital clock",
    category: :ui,
    note: "the local time in seven-segment digits, colon blinking",
    cols: 70,
    rows: 11,
    fps: 10,
    options: %{hour12: false, seconds: true, date: true},
    clock: true
  }

  # A digit is 8 cells wide and 7 tall, about 4:7 once cells are drawn twice as
  # tall as wide. Segments a to g as {row0, row1, col0, col1}.
  @dw 8
  @dh 7
  @segs [
    {0, 0, 2, @dw - 3},
    {1, 2, @dw - 2, @dw - 1},
    {4, 5, @dw - 2, @dw - 1},
    {6, 6, 2, @dw - 3},
    {4, 5, 0, 1},
    {1, 2, 0, 1},
    {3, 3, 2, @dw - 3}
  ]
  @digits {0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F}
  @days {"sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"}
  @months {"january", "february", "march", "april", "may", "june", "july", "august", "september",
           "october", "november", "december"}

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{hour12: hour12, seconds: seconds, date: date}) do
    %{hour12: hour12, seconds: seconds, date: date, top: if(date, do: 1, else: 2), offset: nil}
  end

  # Unlit segments stay faintly visible, like the glass of a real display.
  defp digit(grid, top, x, n) do
    mask = if n < 0, do: 0, else: elem(@digits, n)

    @segs
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {{r0, r1, c0, c1}, s}, grid ->
      ch = if band(bsr(mask, s), 1) == 1, do: "█", else: "░"
      for r <- r0..r1, c <- c0..c1, reduce: grid, do: (grid -> Grid.put(grid, x + c, top + r, ch))
    end)
  end

  defp colon(grid, top, x, on) do
    ch = if on, do: "█", else: "░"
    for r <- [2, 4], c <- [x, x + 1], reduce: grid, do: (grid -> Grid.put(grid, c, top + r, ch))
  end

  @impl true
  def frame(%{hour12: hour12, top: top} = state, t, env) do
    %{cols: cols, rows: rows} = @meta

    # Play time ticks the clock so it steps evenly between frames; the wall
    # clock pulls it back whenever play was paused or fell behind.
    wall = Clock.now_ms(env) / 1000
    offset = state.offset

    offset =
      if offset == nil or wall - (offset + t) > 0.25 or offset + t - wall > 60,
        do: wall - t,
        else: offset

    secs = offset + t
    now = Clock.local(env, trunc(secs * 1000))
    on = secs - floor(secs) < 0.5

    h = now.hour
    pm = h >= 12
    h = if hour12, do: if(rem(h, 12) == 0, do: 12, else: rem(h, 12)), else: h
    pairs = Enum.take([h, now.minute, now.second], if(state.seconds, do: 3, else: 2))
    n = length(pairs)
    width = n * (2 * @dw + 2) + (n - 1) * 6
    x = floor((cols - width) / 2)

    {grid, _} =
      pairs
      |> Enum.with_index()
      |> Enum.reduce({Grid.new(cols, rows), x}, fn {v, i}, {grid, x} ->
        {grid, x} = if i > 0, do: {colon(grid, top, x + 2, on), x + 6}, else: {grid, x}
        # A 12-hour clock leaves its first digit dark rather than showing a zero.
        tens = if i == 0 and hour12 and v < 10, do: -1, else: div(v, 10)

        grid =
          grid
          |> digit(top, x, tens)
          |> digit(top, x + @dw + 2, rem(v, 10))

        {grid, x + 2 * @dw + 2}
      end)

    grid = if state.date, do: date_line(grid, top, now, hour12, pm), else: grid
    {Grid.to_iodata(grid), nil, %{state | offset: offset}}
  end

  defp date_line(grid, top, now, hour12, pm) do
    line =
      elem(@days, Clock.weekday(now)) <>
        " #{now.day} " <> elem(@months, now.month - 1) <> " #{now.year}"

    line = if hour12, do: line <> if(pm, do: "  pm", else: "  am"), else: line
    c0 = floor((@meta.cols - Text.length(line)) / 2)
    Grid.put_string(grid, c0, top + @dh + 1, line)
  end
end
