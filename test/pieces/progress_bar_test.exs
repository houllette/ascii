defmodule AsciiArt.Pieces.ProgressBarTest do
  use ExUnit.Case, async: true

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.ProgressBar,
    variants: [
      %{values: [42]},
      %{values: [0, 33.3, 100, 150, -5, 99.9, 12], style: 2},
      %{cols: 80},
      %{cols: 24, values: [50, 75], style: 3.0},
      %{values: [10, 20], labels: ["one"]},
      %{values: Enum.to_list(1..40), cols: 112.0}
    ]

  use AsciiArt.GoldenCase, slug: "progress-bar", piece: AsciiArt.Pieces.ProgressBar

  defp draw(options, t \\ 0.0) do
    {frame, _} = "progress-bar" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    frame
  end

  test "values are bars at those percentages, a bar each, two rows apiece" do
    frame = draw(%{values: [42, 100], labels: ["copying", "done"], style: 2})
    assert {frame.cols, frame.rows} == {48, 5}
    [_, copying, _, done, _] = frame.lines
    # 26 cells inside the brackets: 42% fills 10 of them.
    assert copying == "  copying   [##########................]   42%  "
    assert done =~ "[##########################]  100%"
  end

  test "values are shown as given, and stay put" do
    assert draw(%{values: [29]}, 0.0).lines == draw(%{values: [29]}, 3.7).lines
    assert Enum.at(draw(%{values: [29]}).lines, 1) =~ " 29%"
  end

  test "cols widens the bars" do
    frame = draw(%{values: [50], cols: 60, style: 2})
    assert frame.cols == 60

    assert Enum.at(frame.lines, 1) =~
             "[" <> String.duplicate("#", 19) <> String.duplicate(".", 19) <> "]"
  end

  test "values taken up while playing move the bars" do
    anim = AsciiArt.new!("progress-bar", options: %{values: [10]})
    anim = AsciiArt.put_options!(anim, values: [90])
    {frame, _} = AsciiArt.frame(anim, 1.0)
    assert Enum.at(frame.lines, 1) =~ " 90%"
  end
end
