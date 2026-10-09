defmodule AsciiArt.Pieces.EqualizerTest do
  use ExUnit.Case, async: true

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Equalizer,
    variants: [
      %{levels: Enum.map(0..18, &(&1 / 18))},
      %{levels: [0.9]},
      %{levels: [2, -1, 0.5]}
    ]

  use AsciiArt.GoldenCase, slug: "equalizer", piece: AsciiArt.Pieces.Equalizer

  defp heights(frame) do
    # Each bar's filled rows, from the bars' columns over the axis.
    for b <- 0..18 do
      x = 3 + b * 3
      Enum.count(0..11, fn r -> frame.lines |> Enum.at(r) |> String.at(x) == "█" end)
    end
  end

  test "describe/1 tells the levels given, low to high" do
    alias AsciiArt.Pieces.Equalizer
    assert Equalizer.describe(%{bpm: 120, levels: []}) == nil

    assert Equalizer.describe(%{bpm: 120, levels: [0.9]}) ==
             "equalizer: 1 level, low to high: 90%"

    assert Equalizer.describe(%{bpm: 120, levels: [2, -1, 0.456]}) ==
             "equalizer: 3 levels, low to high: 100%, 0%, 46%"

    assert Equalizer.describe(%{bpm: 120, levels: Enum.map(0..18, &(&1 / 18))}) ==
             "equalizer: 19 levels, low to high: 0%, 6%, 11%, 17%, 22%, 28%, 33%, 39% and 11 more"
  end

  test "levels set the bars, low to high" do
    anim = AsciiArt.new!("equalizer", options: %{levels: Enum.map(0..18, &(&1 / 18))})
    {frame, _} = AsciiArt.frame(anim, 1.0)
    h = heights(frame)
    assert h == Enum.sort(h)
    assert List.first(h) == 0 and List.last(h) >= 11
  end

  test "new levels taken up while playing: the bars sink from where they were" do
    anim = AsciiArt.new!("equalizer", options: %{levels: [1.0]})
    {full, anim} = AsciiArt.frame(anim, 1.0)
    anim = AsciiArt.put_options!(anim, levels: [0.0])
    {sinking, anim} = AsciiArt.frame(anim, 1.1)
    # Played on, a frame at a time, as the bars fall at most 0.1 s a frame.
    {sunk, _} =
      Enum.reduce(1..60, {nil, anim}, fn i, {_, anim} -> AsciiArt.frame(anim, 1.1 + i / 30) end)

    [a, b, c] = Enum.map([full, sinking, sunk], &(&1 |> heights() |> hd()))
    assert a > b and b > c and c == 0
  end

  describe "parts" do
    alias AsciiArt.Pieces.Equalizer

    # The frame at the last of `times`, played in order (`{:put, options}`
    # takes options up), and its parts.
    defp parts(options, times) do
      {frame, anim} =
        Enum.reduce(times, {nil, AsciiArt.new!("equalizer", options: options)}, fn
          {:put, o}, {f, anim} -> {f, AsciiArt.put_options!(anim, o)}
          t, {_, anim} -> AsciiArt.frame(anim, t)
        end)

      {frame, Equalizer.parts(frame, anim.options)}
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

    test "bars by height, as on a meter; the axis and the frequencies" do
      p = parts(%{levels: Enum.map(0..18, &(&1 / 18))}, [1.0])

      # The last bar is full: seven rows low, three mid, two high.
      assert at(p, 57, 12) == {"bar.low", "█"}
      assert at(p, 58, 6) == {"bar.low", "█"}
      assert at(p, 57, 5) == {"bar.mid", "█"}
      assert at(p, 57, 3) == {"bar.mid", "█"}
      assert at(p, 57, 2) == {"bar.high", "█"}
      assert at(p, 58, 1) == {"bar.high", "█"}
      assert at(p, 56, 1) == {nil, " "}
      assert at(p, 2, 13) == {"axis", "─"}
      assert at(p, 3, 14) == {"scale", "3"}
      assert at(p, 59, 14) == {"scale", "k"}
    end

    test "a peak cap held over a falling bar, and a bar's own thin top" do
      p = parts(%{levels: [1.0]}, [1.0, {:put, levels: [0.3]} | Enum.map(1..9, &(1.0 + &1 / 30))])

      assert at(p, 3, 1) == {"peak", "▁"}
      assert at(p, 4, 1) == {"peak", "▁"}
      assert at(p, 3, 2) == {nil, " "}
      assert at(p, 3, 8) == {"bar.low", "▁"}
      assert at(p, 3, 9) == {"bar.low", "█"}
    end

    test "coloured through the animation" do
      anim = AsciiArt.new!("equalizer", options: %{levels: [1.0]}, parts: true)
      {frame, _} = AsciiArt.frame(anim, 1.0)
      assert AsciiArt.Frame.color_at(frame, 3, 12) == "#3fb950"
      assert AsciiArt.Frame.color_at(frame, 3, 4) == "#d29922"
      assert AsciiArt.Frame.color_at(frame, 3, 1) == "#f85149"
      assert AsciiArt.Frame.color_at(frame, 3, 13) == "#8b949e"
    end
  end
end
