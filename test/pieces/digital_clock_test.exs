defmodule Ascii.Pieces.DigitalClockTest do
  use ExUnit.Case, async: true

  use Ascii.ContractCase,
    piece: Ascii.Pieces.DigitalClock,
    variants: [
      %{hour12: true},
      %{seconds: false, date: false},
      %{hour12: true, date: false},
      %{timer: "down", from: 3, label: "tea"},
      %{timer: "up", from: 359_990, seconds: false},
      %{timer: "up", label: "a label far too long to fit on one line of the clock at all, cut"},
      %{timer: "sideways", from: 5}
    ]

  use Ascii.GoldenCase, slug: "digital-clock", piece: Ascii.Pieces.DigitalClock

  alias Ascii.Frame
  alias Ascii.Pieces.DigitalClock

  # 15:09:26 on Saturday 14 March 2026, half a second in: the colon is dark.
  @now ~U[2026-03-14 15:09:26.535Z]

  # A frame at `now` with `options`, and the part of each of its cells.
  defp parts_at(now, options \\ %{}) do
    anim = Ascii.new!("digital-clock", options: options)
    {frame, _} = Ascii.frame(anim, 0.0, now: now)

    names =
      for runs <- DigitalClock.parts(frame, anim.options) do
        Enum.flat_map(runs, fn {name, text} -> List.duplicate(name, String.length(text)) end)
      end

    {frame, names}
  end

  defp char_at(%Frame{lines: lines}, x, y), do: lines |> Enum.at(y) |> String.at(x)
  defp name_at(names, x, y), do: names |> Enum.at(y) |> Enum.at(x)

  # The column a word starts at on row y.
  defp column(%Frame{lines: lines}, word, y) do
    line = Enum.at(lines, y)
    {at, _} = :binary.match(line, word)
    String.length(binary_part(line, 0, at))
  end

  describe "parts" do
    test "segments lit and unlit, and the colon, by what they show" do
      {frame, names} = parts_at(@now)
      # The hour's 1: its top segment is unlit; the 5 beside it has it lit.
      assert {char_at(frame, 4, 1), name_at(names, 4, 1)} == {"░", "digit.off"}
      assert {char_at(frame, 14, 1), name_at(names, 14, 1)} == {"█", "digit.on"}
      assert {char_at(frame, 8, 2), name_at(names, 8, 2)} == {"█", "digit.on"}
      # Both colons, dark half a second in, and lit before that.
      for x <- [22, 23, 46, 47],
          y <- [3, 5],
          do: assert({char_at(frame, x, y), name_at(names, x, y)} == {"░", "colon.off"})

      {frame, names} = parts_at(~U[2026-03-14 15:09:26.200Z])

      for x <- [22, 23, 46, 47],
          y <- [3, 5],
          do: assert({char_at(frame, x, y), name_at(names, x, y)} == {"█", "colon.on"})

      assert {char_at(frame, 20, 3), name_at(names, 20, 3)} == {" ", nil}
    end

    test "the date, and the hour's half on a 12-hour clock" do
      {frame, names} = parts_at(@now)
      x = column(frame, "saturday", 9)
      assert name_at(names, x, 9) == "date"
      assert name_at(names, column(frame, "2026", 9) + 3, 9) == "date"
      assert name_at(names, x - 1, 9) == nil

      {frame, names} = parts_at(@now, %{hour12: true})
      assert name_at(names, column(frame, "saturday", 9), 9) == "date"
      pm = column(frame, "pm", 9)
      assert {name_at(names, pm, 9), name_at(names, pm + 1, 9)} == {"ampm", "ampm"}
      assert name_at(names, pm - 1, 9) == nil
      # 3 o'clock leaves the hour's first digit dark.
      assert {char_at(frame, 4, 1), name_at(names, 4, 1)} == {"░", "digit.off"}
      assert {char_at(frame, 2, 2), name_at(names, 2, 2)} == {"░", "digit.off"}
    end

    test "without seconds or the date, the digits move down and in" do
      {frame, names} = parts_at(~U[2026-03-14 15:09:26.200Z], %{seconds: false, date: false})
      # Two pairs: the colon is at columns 34 and 35, on rows 4 and 6.
      for x <- [34, 35],
          y <- [4, 6],
          do: assert({char_at(frame, x, y), name_at(names, x, y)} == {"█", "colon.on"})

      assert {char_at(frame, 16, 2), name_at(names, 16, 2)} == {"░", "digit.off"}
      assert {char_at(frame, 20, 3), name_at(names, 20, 3)} == {"█", "digit.on"}
      assert Enum.all?(Enum.at(names, 10), &is_nil/1)
    end

    test "with parts: true, unlit glass is grey and lit segments the ink" do
      {frame, _} =
        "digital-clock" |> Ascii.new!(parts: true) |> Ascii.frame(0.0, now: @now)

      assert Frame.color_at(frame, 4, 1) == "#8b949e"
      assert Frame.color_at(frame, 22, 3) == "#8b949e"
      assert Frame.color_at(frame, 14, 1) == nil
    end
  end

  describe "timers" do
    # The segments of a digit at column x, row top: which are lit, read as
    # the digit they make, or "_" for a dark one.
    @segments [{0, 2}, {1, 6}, {4, 6}, {6, 2}, {4, 0}, {1, 0}, {3, 2}]
    @digits %{
      0x3F => "0",
      0x06 => "1",
      0x5B => "2",
      0x4F => "3",
      0x66 => "4",
      0x6D => "5",
      0x7D => "6",
      0x07 => "7",
      0x7F => "8",
      0x6F => "9",
      0 => "_"
    }

    defp reading(frame, top, pairs) do
      x0 = div(70 - (pairs * 18 + (pairs - 1) * 6), 2)

      for p <- 0..(pairs - 1), into: "" do
        x = x0 + p * 24
        sep = if p > 0, do: ":", else: ""
        sep <> digit_at(frame, x, top) <> digit_at(frame, x + 10, top)
      end
    end

    defp digit_at(frame, x, top) do
      mask =
        for {{dy, dx}, s} <- Enum.with_index(@segments), reduce: 0 do
          mask ->
            if char_at(frame, x + dx, top + dy) == "█", do: mask + Bitwise.bsl(1, s), else: mask
        end

      Map.fetch!(@digits, mask)
    end

    defp play(options, times) do
      anim = Ascii.new!("digital-clock", options: options)

      {frames, _} =
        Enum.map_reduce(times, anim, fn t, anim -> Ascii.frame(anim, t) end)

      frames
    end

    test "a countdown starts on its seconds, runs to zero and flashes there" do
      frames = play(%{timer: "down", from: 65}, [0.0, 0.7, 1.2, 64.2, 65.2, 65.7, 300.1])

      assert Enum.map(frames, &reading(&1, 2, 3)) ==
               ~w(00:01:05 00:01:05 00:01:04 00:00:01 00:00:00 __:__:__ 00:00:00)

      # Without a label the digits sit a row lower, as without a date.
      assert Enum.all?(Enum.at(hd(frames).lines, 1) |> String.graphemes(), &(&1 == " "))
    end

    test "a stopwatch counts up from its seconds, stopping at 99:59:59" do
      frames = play(%{timer: "up", from: 3599, seconds: false}, [0.0, 61.0])
      assert Enum.map(frames, &reading(&1, 2, 2)) == ~w(00:59 01:01)

      [last] = play(%{timer: "up", from: 359_990}, [3600.0])
      assert reading(last, 2, 3) == "99:59:59"
    end

    test "the colons blink as a timer runs" do
      [lit, dark] = play(%{timer: "up"}, [0.2, 0.7])
      assert {char_at(lit, 22, 4), char_at(dark, 22, 4)} == {"█", "░"}
    end

    test "a label beneath, in its part" do
      anim = Ascii.new!("digital-clock", options: %{timer: "down", from: 300, label: "tea"})
      {frame, anim} = Ascii.frame(anim, 0.0)
      assert reading(frame, 1, 3) == "00:05:00"
      assert String.trim(Enum.at(frame.lines, 9)) == "tea"
      rows = DigitalClock.parts(frame, anim.options)
      assert [{nil, _}, {"label", "tea"}, {nil, _}] = Enum.at(rows, 9)
    end

    test "a new label carries on; a new start or another timer starts afresh" do
      anim = Ascii.new!("digital-clock", options: %{timer: "up", from: 10})
      {_, anim} = Ascii.frame(anim, 0.0)
      {frame, anim} = Ascii.frame(anim, 5.0)
      assert reading(frame, 2, 3) == "00:00:15"

      labelled = Ascii.put_options!(anim, label: "lap")
      {frame, _} = Ascii.frame(labelled, 6.0)
      assert reading(frame, 1, 3) == "00:00:16"

      restarted = Ascii.put_options!(anim, from: 100)
      {_, restarted} = Ascii.frame(restarted, 6.0)
      {frame, _} = Ascii.frame(restarted, 8.5)
      assert reading(frame, 2, 3) == "00:01:42"

      {frame, _} = anim |> Ascii.put_options!(timer: "down") |> Ascii.frame(6.0)
      assert reading(frame, 2, 3) == "00:00:10"
    end

    test "a timer keeps play time, not the clock" do
      anim = Ascii.new!("digital-clock", options: %{timer: "down", from: 90})
      {a, _} = Ascii.frame(anim, 3.0, now: @now)
      {b, _} = Ascii.frame(anim, 3.0, now: ~U[2030-01-01 00:00:00Z])
      assert a.text == b.text
    end

    test "anything else is the clock" do
      {a, _} =
        "digital-clock" |> Ascii.new!(options: %{timer: "x"}) |> Ascii.frame(0.0, now: @now)

      {b, _} = "digital-clock" |> Ascii.new!() |> Ascii.frame(0.0, now: @now)
      assert a.text == b.text
    end

    test "in words: the timer and where it starts" do
      describe = &DigitalClock.describe(Map.merge(DigitalClock.meta().options, &1))
      assert describe.(%{}) == nil
      assert describe.(%{timer: "down", from: 300, label: "tea"}) == "tea: countdown from 5:00"
      assert describe.(%{timer: "down", from: 3725}) == "countdown from 1:02:05"
      assert describe.(%{timer: "up"}) == "stopwatch"
      assert describe.(%{timer: "up", from: 90}) == "stopwatch from 1:30"
    end
  end
end
