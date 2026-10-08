defmodule AsciiArt.Pieces.HeatmapTest do
  use ExUnit.Case, async: true

  @counts Enum.map(0..200, &max(rem(&1 * 7 + div(&1, 3), 11) - 3, 0))

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Heatmap,
    variants: [
      %{counts: @counts, date: "2026-10-07"},
      %{counts: [0, 0, 0], date: "2024-02-29", weeks: 12},
      %{counts: [5_000_000, 1], weeks: 97, unit: "requests"},
      %{counts: [1, 2, 3], date: "not a date"}
    ]

  use AsciiArt.GoldenCase, slug: "heatmap", piece: AsciiArt.Pieces.Heatmap

  defp draw(options, t \\ 1.0) do
    {frame, _} = "heatmap" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    frame
  end

  test "counts shade their days in four steps of the busiest, ending on the date" do
    # 2026-10-07 is a Wednesday: the last column holds Monday to Wednesday.
    frame = draw(%{counts: [0, 1, 2, 4], date: "2026-10-07", weeks: 12, unit: "deploys"})
    assert frame.cols == 30
    column = for r <- 2..8, do: frame.lines |> Enum.at(r) |> String.at(28)
    assert column == ["░", "▒", "█", " ", " ", " ", " "]
    assert Enum.at(frame.lines, 8) |> String.at(26) == "·"
    assert frame.text =~ "7 deploys in the last 12"
  end

  test "counts stand still; upstream's calendar fills in" do
    assert draw(%{counts: @counts, date: "2026-10-07"}, 1.0).text ==
             draw(%{counts: @counts, date: "2026-10-07"}, 30.0).text

    refute draw(%{}, 1.0).text == draw(%{}, 30.0).text
  end

  test "without a date, the counts end today" do
    now = ~U[2026-10-07 12:00:00Z]
    anim = AsciiArt.new!("heatmap", options: %{counts: [4], weeks: 12})
    {a, _} = AsciiArt.frame(anim, 0.0, now: now)
    b = draw(%{counts: [4], weeks: 12, date: "2026-10-07"})
    assert a.text == b.text
  end
end
