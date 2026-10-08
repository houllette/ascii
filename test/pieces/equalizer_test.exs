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
end
