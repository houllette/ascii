defmodule AsciiArt.Pieces.GaugeTest do
  use ExUnit.Case, async: true

  alias AsciiArt.Pieces.Gauge

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Gauge,
    variants: [
      %{value: 40},
      %{value: -10},
      %{value: 1000, min: 0, max: 50, unit: "rpm"},
      %{value: 5, min: 5, max: 5},
      %{label: String.duplicate("long label ", 6), unit: " units per second", min: -50},
      %{cols: 43, rows: 15, value: 63},
      %{cols: 120, rows: 30, value: 30, label: "requests", unit: "/s", max: 400},
      %{cols: 200, rows: 15},
      %{cols: 43, rows: 100, value: 99},
      %{cols: 10, rows: 3, value: 50},
      %{cols: 60.7, rows: 21.2}
    ]

  use AsciiArt.GoldenCase, slug: "gauge", piece: AsciiArt.Pieces.Gauge

  defp text(anim, t), do: anim |> AsciiArt.frame(t) |> elem(0) |> Map.get(:text)

  test "a value is a reading: the readout shows it, and the needle settles on it" do
    anim = AsciiArt.new!("gauge", options: %{value: 72})
    assert text(anim, 0.0) =~ "72%"
    # Settled: two late frames agree, and agree with a gauge that started at 72.
    assert text(anim, 9.0) == text(anim, 9.5)
  end

  test "a new reading taken up while playing swings the needle on from where it was" do
    anim = AsciiArt.new!("gauge", options: %{value: 20})
    {before, anim} = AsciiArt.frame(anim, 0.3)
    anim = AsciiArt.put_options!(anim, value: 90)
    {after_update, anim} = AsciiArt.frame(anim, 0.3)

    # At once only the readout changes: the needle has not jumped.
    changed =
      for {a, b, row} <- Enum.zip([before.lines, after_update.lines, 0..17]), a != b, do: row

    assert changed == [15]
    assert Enum.at(after_update.lines, 15) =~ "90%"

    # Then it swings round, and settles with the band filled almost to the end.
    settled = text(anim, 6.0)
    assert count(settled, "▓") > 5 * count(settled, "░")
  end

  defp count(text, s), do: length(String.split(text, s)) - 1

  test "without a value it plays upstream's readings" do
    refute text(AsciiArt.new!("gauge"), 0.0) == text(AsciiArt.new!("gauge"), 2.0)
  end

  describe "cols and rows" do
    # A gauge settled on `value`, at a size.
    defp settled(options) do
      anim = AsciiArt.new!("gauge", options: options)
      {_, anim} = AsciiArt.frame(anim, 0.0)
      {frame, _} = AsciiArt.frame(anim, 60.0)
      frame
    end

    test "the frame is the size asked for, the dial as large as fits it, centred" do
      frame = settled(%{value: 63, cols: 120, rows: 30})
      assert {frame.cols, frame.rows} == {120, 30}
      # A rim of 46 pixels about the pivot at column 59, pixel 51: its top
      # in row 2, its ends in row 25, the readout and label beneath.
      assert String.slice(Enum.at(frame.lines, 2), 53, 13) == String.duplicate("▄", 13)
      assert String.at(Enum.at(frame.lines, 25), 13) == "█"
      assert String.at(Enum.at(frame.lines, 25), 105) == "█"
      assert String.slice(Enum.at(frame.lines, 27), 58, 3) == "63%"
      assert String.slice(Enum.at(frame.lines, 28), 58, 4) == "load"
      assert frame.lines |> Enum.at(29) |> String.trim() == ""
    end

    test "the rest of a frame wider or taller than the dial is blank around it" do
      wide = settled(%{value: 63, cols: 200, rows: 15})
      small = settled(%{value: 63, cols: 43, rows: 15})
      pad = String.duplicate(" ", 78)
      assert Enum.map(small.lines, &(pad <> &1 <> pad <> " ")) == wide.lines

      tall = settled(%{value: 63, cols: 43, rows: 41})
      blank = String.duplicate(" ", 43)

      assert tall.lines ==
               List.duplicate(blank, 13) ++ small.lines ++ List.duplicate(blank, 13)
    end

    test "never smaller than the least dial, of radius 16" do
      assert AsciiArt.new!("gauge", options: %{cols: 10, rows: 3}) |> then(&{&1.cols, &1.rows}) ==
               {43, 15}

      assert Gauge.size(%{cols: 55.9, rows: 18.2}) == {55, 18}
    end

    test "upstream's size draws upstream's dial" do
      assert text(AsciiArt.new!("gauge", options: %{cols: 55, rows: 18}), 1.0) ==
               text(AsciiArt.new!("gauge"), 1.0)
    end

    test "taken up while playing, the needle carries on in the new dial" do
      anim = AsciiArt.new!("gauge", options: %{value: 20})
      {_, anim} = AsciiArt.frame(anim, 0.0)
      {_, anim} = AsciiArt.frame(anim, 9.0)
      anim = AsciiArt.put_options!(anim, cols: 120, rows: 30, value: 20)
      assert {anim.cols, anim.rows} == {120, 30}
      {frame, _} = AsciiArt.frame(anim, 9.1)
      assert frame.text == settled(%{value: 20, cols: 120, rows: 30}).text
    end
  end

  test "describe/1 tells the reading as the readout shows it" do
    options = AsciiArt.meta!("gauge").options
    assert Gauge.describe(options) == nil
    assert Gauge.describe(%{options | value: 71.6}) == "load: 72%"

    assert Gauge.describe(%{options | value: 1000, label: "fan", unit: "rpm"}) ==
             "fan: 1000 rpm"

    assert Gauge.describe(%{options | value: -3, label: " ", unit: "°"}) == "gauge: -3°"
  end

  describe "parts" do
    # The frame at the last of `times`, played in order, and its parts.
    defp parts(options, times) do
      {frame, anim} =
        Enum.reduce(times, {nil, AsciiArt.new!("gauge", options: options)}, fn t, {_, anim} ->
          AsciiArt.frame(anim, t)
        end)

      {frame, Gauge.parts(frame, anim.options)}
    end

    # The part of the cell at column x, row y, and the character there.
    defp at({frame, rows}, x, y) do
      part =
        rows
        |> Enum.at(y)
        |> Enum.flat_map(fn {name, text} -> List.duplicate(name, String.length(text)) end)
        |> Enum.at(x)

      {part, frame.lines |> Enum.at(y) |> String.at(x)}
    end

    test "the dial, its ticks and scale, the band and the readout" do
      # Settled on 30: the band filled to it, the needle up and to the left.
      p = parts(%{value: 30}, [0.0, 9.0])

      assert at(p, 23, 2) == {"dial", "▄"}
      assert at(p, 27, 6) == {"axis", "█"}
      assert at(p, 25, 6) == {"axis.minor", "·"}
      assert at(p, 6, 6) == {"scale", "2"}
      assert at(p, 5, 15) == {"scale", "0"}
      assert at(p, 48, 15) == {"scale", "1"}
      assert at(p, 14, 6) == {"bar", "▓"}
      assert at(p, 20, 4) == {"track", "░"}
      assert at(p, 26, 15) == {"value", "3"}
      assert at(p, 28, 15) == {"unit", "%"}
      assert at(p, 26, 16) == {"label", "l"}
      assert at(p, 0, 0) == {nil, " "}
    end

    test "the needle, over a tick it crosses, and its hub" do
      p = parts(%{value: 30}, [0.0, 9.0])
      # Alone, and adding to the tick at 30.
      assert at(p, 19, 7) == {"needle", "▄"}
      assert at(p, 18, 7) == {"needle", "█"}
      assert at(p, 27, 13) == {"needle.hub", "█"}

      # Upright, it covers the tick at 50 without adding to it: still the needle.
      p = parts(%{value: 50}, [0.0, 9.0])
      assert at(p, 27, 6) == {"needle", "█"}
      assert at(p, 27, 9) == {"needle", "█"}
      # The tick at 30 is a tick again.
      assert at(p, 18, 7) == {"axis", "▄"}
    end

    test "a unit after a space, a scale in other units" do
      p = parts(%{value: 1000, min: 0, max: 50, unit: "rpm"}, [0.0, 9.0])
      assert at(p, 24, 15) == {"value", "1"}
      assert at(p, 27, 15) == {"value", "0"}
      assert at(p, 28, 15) == {nil, " "}
      assert at(p, 29, 15) == {"unit", "r"}
      assert at(p, 31, 15) == {"unit", "m"}
      assert at(p, 6, 6) == {"scale", "1"}
      assert at(p, 49, 15) == {"scale", "5"}
    end

    test "upstream's readings: the readout is found wherever it has got to" do
      p = parts(%{}, [1.0])
      {frame, _} = p
      assert Enum.at(frame.lines, 15) =~ "17%"
      assert at(p, 26, 15) == {"value", "1"}
      assert at(p, 27, 15) == {"value", "7"}
      assert at(p, 28, 15) == {"unit", "%"}
    end

    # The needle's pixels at a reading, as the piece draws it (a reference
    # port of frame/3's needle).
    defp needle_pixels(v) do
      a = :math.pi() * (1 - v / 100)

      MapSet.new(0..56, fn j ->
        r = 2 + j * 0.25

        {AsciiArt.JSMath.round(27 + r * :math.cos(a)),
         AsciiArt.JSMath.round(27 - r * :math.sin(a))}
      end)
    end

    test "over a sweep of readings, the needle is never taken for a tick, nor a tick for it" do
      unsure =
        for q <- 0..400, reduce: 0 do
          unsure ->
            v = q / 4
            # Settled for good: the spring has died away below a float's ulp.
            {frame, _rows} = p = parts(%{value: v}, [0.0, 60.0])
            needle = needle_pixels(v)

            cells =
              for y <- 0..14, x <- 0..54, {part, ch} = at(p, x, y), ch in ~w(▀ ▄ █) do
                on? = MapSet.member?(needle, {x, 2 * y}) or MapSet.member?(needle, {x, 2 * y + 1})
                {part, on?, {x, y, frame.t}}
              end

            for {part, on?, where} <- cells do
              if part == "needle", do: assert(on?, "needle off the needle at #{inspect(where)}")
              if part == "axis", do: refute(on?, "a tick under the needle at #{inspect(where)}")
            end

            if Enum.any?(cells, &(elem(&1, 0) == nil)), do: unsure + 1, else: unsure
        end

      # Some crossings cannot be told from the picture, and are in no part.
      assert unsure < 401 * 0.06
    end

    # The needle's pixels at a reading on a dial of radius `r` about
    # pivot `{cx, cy}`.
    defp needle_pixels(v, r, {cx, cy}) do
      a = :math.pi() * (1 - v / 100)

      MapSet.new(0..(4 * (r - 8)), fn j ->
        d = 2 + j * 0.25

        {AsciiArt.JSMath.round(cx + d * :math.cos(a)),
         AsciiArt.JSMath.round(cy - d * :math.sin(a))}
      end)
    end

    test "on a dial of another size, the needle and the ticks are told apart as ever" do
      size = %{cols: 120, rows: 30}
      p = parts(Map.put(size, :value, 30), [0.0, 60.0])
      assert at(p, 59, 25) == {"needle.hub", "█"}
      assert at(p, 58, 27) == {"value", "3"}
      assert at(p, 60, 27) == {"unit", "%"}
      assert at(p, 13, 27) == {"scale", "0"}
      assert at(p, 58, 28) == {"label", "l"}

      unsure =
        for v <- 0..100//4, reduce: 0 do
          unsure ->
            {frame, _rows} = p = parts(Map.put(size, :value, v), [0.0, 60.0])
            needle = needle_pixels(v, 46, {59, 51})

            cells =
              for y <- 0..25, x <- 0..119, {part, ch} = at(p, x, y), ch in ~w(▀ ▄ █) do
                on? = MapSet.member?(needle, {x, 2 * y}) or MapSet.member?(needle, {x, 2 * y + 1})
                {part, on?, {x, y, frame.t}}
              end

            for {part, on?, where} <- cells do
              if part == "needle", do: assert(on?, "needle off the needle at #{inspect(where)}")
              if part == "axis", do: refute(on?, "a tick under the needle at #{inspect(where)}")
              if part == "dial", do: refute(on?, "the rim under the needle at #{inspect(where)}")
            end

            if Enum.any?(cells, &(elem(&1, 0) == nil)), do: unsure + 1, else: unsure
        end

      assert unsure <= 2
    end

    test "coloured through the animation" do
      anim = AsciiArt.new!("gauge", options: %{value: 30}, parts: %{needle: "#d29922"})
      {_, anim} = AsciiArt.frame(anim, 0.0)
      {frame, _} = AsciiArt.frame(anim, 9.0)
      assert AsciiArt.Frame.color_at(frame, 19, 7) == "#d29922"
      assert AsciiArt.Frame.color_at(frame, 27, 13) == "#d29922"
      assert AsciiArt.Frame.color_at(frame, 23, 2) == nil
    end
  end
end
