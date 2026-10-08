defmodule AsciiArt.Pieces.CandlesticksTest do
  use ExUnit.Case, async: true

  @candles for i <- 0..19,
               o = 61_000 + i * 37.5,
               c = o + if(rem(i, 3) == 0, do: -80, else: 120),
               do: [o, max(o, c) + 150, min(o, c) - 120, c]

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Candlesticks,
    variants: [
      %{candles: @candles, times: Enum.map(0..19, &"#{10 + div(&1, 4)}:#{rem(&1, 4) * 15}")},
      %{candles: [[1.5, 1.7, 1.4, 1.6]], digits: 4},
      %{candles: [[0.0001, 0.0002, 0.00005, 0.00015], [3], []]},
      %{candles: [[100, 100, 100, 100], [100, 100, 100, 100]], digits: 0}
    ]

  use AsciiArt.GoldenCase, slug: "candlesticks", piece: AsciiArt.Pieces.Candlesticks

  defp draw(options, t \\ 1.0) do
    {frame, _} = "candlesticks" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
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
end
