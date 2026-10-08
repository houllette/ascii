defmodule AsciiArt.Pieces.Calendar do
  @moduledoc """
  This month like cal, today bracketed, time ticking below.

  This month laid out like the cal command, today in brackets, with the
  weekday and the running time along the bottom.

  Reads the clock from `env.now` (see `AsciiArt.Kit.Clock`).

  Ported from `src/pieces/calendar.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Kit.{Clock, Text}

  @meta %AsciiArt.Meta{
    name: "calendar",
    category: :ui,
    note: "this month like cal, today bracketed, time ticking below",
    cols: 32,
    rows: 13,
    fps: 8,
    options: %{monday: false, time: true},
    clock: true
  }

  @days {"sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"}
  @months {"january", "february", "march", "april", "may", "june", "july", "august", "september",
           "october", "november", "december"}
  # Left margin; the grid is 7 cells of 4.
  @l 2

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{monday: monday, time: time}) do
    order = if monday, do: [1, 2, 3, 4, 5, 6, 0], else: [0, 1, 2, 3, 4, 5, 6]
    %{order: order, time: time, offset: nil, key: nil, page: []}
  end

  defp pad(s),
    do: (String.duplicate(" ", @l) <> s) |> Text.pad_end(@meta.cols) |> Text.slice(0, @meta.cols)

  defp centre(s), do: pad(String.duplicate(" ", max(0, floor((28 - Text.length(s)) / 2))) <> s)

  # The month only changes at midnight, so the grid is built once a day.
  defp build(order, y, m, d) do
    first = Date.new!(y, m, 1)
    lead = rem(Clock.weekday(first) - hd(order) + 7, 7)
    count = Date.days_in_month(first)

    weeks =
      for w <- 0..5 do
        pad(
          for c <- 0..6, into: "" do
            n = w * 7 + c - lead + 1

            cond do
              n < 1 or n > count -> "    "
              n == d and n < 10 -> " [#{n}]"
              n == d -> "[#{n}]"
              true -> " " <> Text.pad_start(Integer.to_string(n), 2) <> " "
            end
          end
        )
      end

    rule = pad(String.duplicate("─", 28))

    [
      String.duplicate(" ", @meta.cols),
      centre(elem(@months, m - 1) <> " " <> Integer.to_string(y)),
      rule,
      pad(Enum.map_join(order, &(" " <> Text.slice(elem(@days, &1), 0, 2) <> " ")))
    ] ++ weeks ++ [rule]
  end

  @impl true
  def frame(%{order: order, time: time} = state, t, env) do
    # Play time ticks the clock so it steps evenly between frames; the wall
    # clock pulls it back whenever play was paused or fell behind.
    wall = Clock.now_ms(env) / 1000
    offset = state.offset

    offset =
      if offset == nil or wall - (offset + t) > 0.25 or offset + t - wall > 60,
        do: wall - t,
        else: offset

    now = Clock.local(env, trunc((offset + t) * 1000))
    %{year: y, month: m, day: d} = now
    key = {y, m, d}
    page = if key == state.key, do: state.page, else: build(order, y, m, d)

    day = elem(@days, Clock.weekday(now)) <> " " <> Integer.to_string(d)
    clock = if time, do: Enum.map_join([now.hour, now.minute, now.second], ":", &two/1), else: ""
    foot = pad(" " <> day <> Text.pad_start(clock, 26 - Text.length(day)))
    lines = Enum.take(page ++ [foot, String.duplicate(" ", @meta.cols)], @meta.rows)

    {Enum.intersperse(lines, ?\n), nil, %{state | offset: offset, key: key, page: page}}
  end

  defp two(n), do: n |> Integer.to_string() |> Text.pad_start(2, "0")
end
