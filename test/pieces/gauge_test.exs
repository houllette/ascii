defmodule AsciiArt.Pieces.GaugeTest do
  use ExUnit.Case, async: true

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Gauge,
    variants: [
      %{value: 40},
      %{value: -10},
      %{value: 1000, min: 0, max: 50, unit: "rpm"},
      %{value: 5, min: 5, max: 5}
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
end
