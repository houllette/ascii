defmodule Ascii.Pieces.CandlesticksTest do
  use ExUnit.Case, async: true

  @candles for i <- 0..19,
               o = 61_000 + i * 37.5,
               c = o + if(rem(i, 3) == 0, do: -80, else: 120),
               do: [o, max(o, c) + 150, min(o, c) - 120, c]

  @millions [
    [16_500_000.0, 16_700_000.0, 16_400_000.0, 16_600_000.0],
    [16_600_000.0, 17_000_000.0, 15_000_000.0, 16_000_000]
  ]

  use Ascii.ContractCase,
    piece: Ascii.Pieces.Candlesticks,
    variants: [
      %{candles: @candles, times: Enum.map(0..19, &"#{10 + div(&1, 4)}:#{rem(&1, 4) * 15}")},
      %{candles: [[1.5, 1.7, 1.4, 1.6]], digits: 4},
      %{candles: [[0.0001, 0.0002, 0.00005, 0.00015], [3], []]},
      %{candles: [[100, 100, 100, 100], [100, 100, 100, 100]], digits: 0},
      %{candles: [[100, 104, 96, 103], [103, 104, 99, 99.96]]},
      %{candles: [[0, 1, 0, 0]]},
      %{candles: [[0, 0, -1, -1]]},
      %{start: 1.0e8, digits: 4},
      %{candles: @millions, digits: 2},
      %{candles: [[-2.5e12, 1.0e15, -1.0e15, 7.0e14], [1, 2, 0.5, 1.5]], digits: 8},
      %{start: 1.0e15, digits: 8}
    ]

  use Ascii.GoldenCase, slug: "candlesticks", piece: Ascii.Pieces.Candlesticks

  defp draw(options, t \\ 1.0) do
    {frame, _} = "candlesticks" |> Ascii.new!(options: options) |> Ascii.frame(t)
    frame
  end

  test "candles given are drawn, the last against the axis, with its prices on top" do
    frame = draw(%{candles: [[100, 110, 95, 105], [105, 108, 90, 92]], digits: 0})
    assert hd(frame.lines) =~ "o 105   h 108   l 90   c 92   -12.38%"
    # The falling candle is solid, in the last slot (columns 56 to 58).
    assert Enum.any?(frame.lines, &(String.slice(&1, 56, 3) == "███"))
    # And the price line runs out to the axis.
    assert frame.text =~ "┄├ 92"
  end

  test "a scale that fits prices of any size" do
    frame = draw(%{candles: @candles, digits: 0})
    assert frame.text =~ ~r/┤ 61\d00/
  end

  test "candles stand still; upstream's market moves" do
    assert draw(%{candles: @candles}, 1.0).text == draw(%{candles: @candles}, 9.0).text
    refute draw(%{}, 1.0).text == draw(%{}, 9.0).text
  end

  describe "in words" do
    defp told(options),
      do: "candlesticks" |> Ascii.new!(options: options) |> Ascii.describe()

    test "the candles given: how many, the last one's prices and change" do
      assert told(%{candles: [[1, 2, 0.5, 1.5], [100, 104, 96, 103]], times: ["09:30", "09:35"]}) ==
               "candlesticks: 2 candles, the last at 09:35: " <>
                 "open 100.00, high 104.00, low 96.00, close 103.00, +3.00%"

      assert told(%{candles: [[0, 1, 0, 0]], digits: 0}) ==
               "candlesticks: 1 candle, the last: open 0, high 1, low 0, close 0"
    end

    test "upstream's market, what the piece is" do
      assert told(%{start: 50}) =~ "candlesticks: hollow up candles"
    end
  end

  describe "parts" do
    alias Ascii.Frame
    alias Ascii.Kit.Text
    alias Ascii.Pieces.Candlesticks

    defp parts(options, t \\ 0.0) do
      {frame, anim} = "candlesticks" |> Ascii.new!(options: options) |> Ascii.frame(t)
      {frame, Candlesticks.parts(frame, anim.options)}
    end

    # The part of row y's cell at column x.
    defp part_at(rows, x, y) do
      rows
      |> Enum.at(y)
      |> Enum.flat_map(fn {name, text} -> List.duplicate(name, Text.length(text)) end)
      |> Enum.at(x)
    end

    test "the quote: each price's letter and value, and the change, down" do
      {frame, rows} = parts(%{})
      assert hd(frame.lines) =~ "o 99.75   h 99.75   l 99.59   c 99.59   -0.15%"

      assert hd(rows) == [
               {"label", "o"},
               {nil, " "},
               {"value", "99.75"},
               {nil, "   "},
               {"label", "h"},
               {nil, " "},
               {"value", "99.75"},
               {nil, "   "},
               {"label", "l"},
               {nil, " "},
               {"value", "99.59"},
               {nil, "   "},
               {"label", "c"},
               {nil, " "},
               {"value", "99.59"},
               {nil, "   "},
               {"change.down", "-0.15%"},
               {nil, String.duplicate(" ", 24)}
             ]
    end

    test "each candle, wicks and all, hollow up or solid down" do
      {frame, rows} = parts(%{})
      assert frame.lines |> Enum.at(7) |> String.slice(0, 42) =~ ~r/^ │ +┌─┐ ███  │$/
      assert frame.lines |> Enum.at(8) |> String.slice(40, 3) == "███"

      # The first candle's wick over its solid body; a hollow one; the
      # wick over the solid body at columns 40 to 42.
      assert part_at(rows, 1, 7) == "candle.down"
      assert part_at(rows, 0, 8) == "candle.down"
      assert part_at(rows, 32, 7) == "candle.up"
      assert part_at(rows, 33, 7) == "candle.up"
      assert part_at(rows, 36, 7) == "candle.down"
      assert part_at(rows, 41, 7) == "candle.down"
      assert part_at(rows, 2, 7) == nil
    end

    test "the last price's line out to the axis, the axis and its scale, the times" do
      {frame, rows} = parts(%{})
      assert Enum.at(frame.lines, 13) |> String.slice(52, 18) == "│ │ ███┄┄├ 99.59  "

      assert Enum.take(Enum.at(rows, 13), -7) == [
               {"candle.up", "│"},
               {nil, " "},
               {"candle.up", "│"},
               {nil, " "},
               {"candle.down", "███"},
               {"price", "┄┄├ 99.59"},
               {nil, "  "}
             ]

      assert Enum.take(Enum.at(rows, 6), -4) == [
               {"axis", "┤"},
               {nil, " "},
               {"scale", "101.00"},
               {nil, " "}
             ]

      assert Enum.take(Enum.at(rows, 2), -2) == [{"axis", "│"}, {nil, String.duplicate(" ", 8)}]
      assert [{"axis", "─┴" <> _}, {nil, "        "}] = Enum.at(rows, 19)

      assert [
               {nil, _},
               {"scale", "12:50"},
               {nil, _},
               {"scale", "13:10"},
               {nil, _},
               {"scale", "13:30"},
               {nil, _}
             ] = Enum.at(rows, 20)
    end

    test "a price shorter than the axis label it covers leaves the label's end on the scale" do
      {frame, rows} = parts(%{candles: [[100, 104, 96, 103], [103, 104, 99, 99.96]]})
      assert Enum.at(frame.lines, 10) =~ "███┄┄├ 99.960 "

      assert Enum.take(Enum.at(rows, 10), -4) == [
               {"candle.down", "███"},
               {"price", "┄┄├ 99.96"},
               {"scale", "0"},
               {nil, " "}
             ]
    end

    test "a quote too long for the frame, its prices fitted alike; a wick off the chart, nil" do
      {frame, rows} = parts(%{start: 1.0e8, digits: 4}, 1.0)

      assert hd(frame.lines) ==
               "o 99747536.5   h 100297606.0   l 99592950.1   c 100101469.7   +0.35%  "

      assert Enum.at(frame.lines, 1) |> String.at(53) == "│"

      assert [
               {"label", "c"},
               {nil, " "},
               {"value", "100101469.7"},
               {nil, "   "},
               {"change.up", "+0.35%"},
               {nil, "  "}
             ] =
               Enum.drop(hd(rows), 12)

      assert part_at(rows, 53, 1) == nil
    end

    test "prices too wide for the axis are written compactly, and labelled" do
      {frame, rows} = parts(%{candles: @millions})

      assert hd(frame.lines) ==
               "o 16600000.00   h 17000000.00   l 15000000.00   c 16000000.00   -3.61%"

      assert Enum.at(frame.lines, 3) |> String.slice(61, 9) == "┤ 18M    "
      assert Enum.at(frame.lines, 13) |> String.slice(56, 14) == "███┄┄├ 16M    "

      assert Enum.take(Enum.at(rows, 3), -4) ==
               [{"axis", "┤"}, {nil, " "}, {"scale", "18M"}, {nil, "    "}]

      assert Enum.take(Enum.at(rows, 13), -2) == [{"price", "┄┄├ 16M"}, {nil, "    "}]
    end

    test "with parts: true, up green, down red, the price blue, axis and labels grey" do
      {frame, _} = "candlesticks" |> Ascii.new!(parts: true) |> Ascii.frame(0.0)

      assert Frame.color_at(frame, 32, 7) == "#3fb950"
      assert Frame.color_at(frame, 0, 8) == "#f85149"
      assert Frame.color_at(frame, 59, 13) == "#58a6ff"
      assert Frame.color_at(frame, 61, 6) == "#8b949e"
      assert Frame.color_at(frame, 0, 0) == "#8b949e"
      assert Frame.color_at(frame, 2, 0) == nil
      assert Frame.color_at(frame, 40, 0) == "#f85149"
    end
  end
end
