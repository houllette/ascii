defmodule Ascii.Pieces.ProgressBarTest do
  use ExUnit.Case, async: true

  use Ascii.ContractCase,
    piece: Ascii.Pieces.ProgressBar,
    variants: [
      %{values: [42]},
      %{values: [0, 33.3, 100, 150, -5, 99.9, 12], style: 2},
      %{cols: 80},
      %{cols: 24, values: [50, 75], style: 3.0},
      %{values: [10, 20], labels: ["one"]},
      %{values: Enum.to_list(1..40), cols: 112.0}
    ]

  use Ascii.GoldenCase, slug: "progress-bar", piece: Ascii.Pieces.ProgressBar

  defp draw(options, t \\ 0.0) do
    {frame, _} = "progress-bar" |> Ascii.new!(options: options) |> Ascii.frame(t)
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
    anim = Ascii.new!("progress-bar", options: %{values: [10]})
    anim = Ascii.put_options!(anim, values: [90])
    {frame, _} = Ascii.frame(anim, 1.0)
    assert Enum.at(frame.lines, 1) =~ " 90%"
  end

  describe "in words" do
    defp told(options),
      do: "progress-bar" |> Ascii.new!(options: options) |> Ascii.describe()

    test "each value given, its label and its percent as the bar shows it" do
      assert told(%{values: [34.7, 100, 150, -3], labels: ["fetch", "", "x"]}) ==
               "progress: fetch 34%, bar 2 100%, x 100%, bar 4 0%"
    end

    test "past eight bars, how many more" do
      assert told(%{values: Enum.to_list(1..10), labels: []}) ==
               "progress: bar 1 1%, bar 2 2%, bar 3 3%, bar 4 4%, bar 5 5%, bar 6 6%, " <>
                 "bar 7 7%, bar 8 8%, and 2 more"
    end

    test "without values, what the piece is" do
      assert told(%{}) =~ "progress bar: five bar styles"
    end
  end

  describe "parts" do
    alias Ascii.Frame
    alias Ascii.Pieces.ProgressBar

    defp parts(options, t \\ 0.0) do
      {frame, anim} = "progress-bar" |> Ascii.new!(options: options) |> Ascii.frame(t)
      {frame, ProgressBar.parts(frame, anim.options)}
    end

    test "a bar's row: its label, the bar's ends, filled and empty cells, the percent" do
      {_frame, rows} = parts(%{values: [42, 100], labels: ["copying", "done"], style: 2})

      assert Enum.at(rows, 0) == [{nil, String.duplicate(" ", 48)}]

      assert Enum.at(rows, 1) == [
               {nil, "  "},
               {"label", "copying"},
               {nil, "   "},
               {"frame", "["},
               {"bar", String.duplicate("#", 10)},
               {"track", String.duplicate(".", 16)},
               {"frame", "]"},
               {nil, "   "},
               {"value", "42"},
               {"unit", "%"},
               {nil, "  "}
             ]
    end

    test "a bar at 100% is done" do
      {_frame, rows} = parts(%{values: [42, 100], labels: ["copying", "done"], style: 2})

      assert [
               {nil, "  "},
               {"label", "done"},
               {nil, "      "},
               {"frame", "["},
               {"bar.done", bar},
               {"frame", "]"},
               {nil, "  "},
               {"value", "100"} | _
             ] = Enum.at(rows, 3)

      assert bar == String.duplicate("#", 26)
    end

    test "a smooth bar's partial cell is in the bar, its right edge, drawn the same, is not" do
      # 50.48% of 26 cells, in eighths, is 13 cells and one eighth: a "▏".
      {frame, rows} = parts(%{values: [50.48], style: 1})
      assert Enum.at(frame.lines, 1) =~ "▏" <> String.duplicate(" ", 12) <> "▏"

      assert [
               {nil, "  "},
               {"label", "fetching"},
               {nil, "  "},
               {"frame", "▕"},
               {"bar", bar},
               {nil, gap},
               {"frame", "▏"} | _
             ] = Enum.at(rows, 1)

      assert bar == String.duplicate("█", 13) <> "▏"
      assert gap == String.duplicate(" ", 12)
    end

    test "every style's cells as played, the label cut as drawn" do
      {frame, rows} = parts(%{labels: ["a long label", "", "", "x", ""]})
      assert Enum.at(frame.lines, 1) =~ "  a long la "

      assert [{nil, "  "}, {"label", "a long la"}, {nil, " "}, {"frame", "["} | _] =
               Enum.at(rows, 1)

      assert [{nil, "            "}, {"frame", "▕"} | _] = Enum.at(rows, 3)
      # Lamps, lit and not, with gaps between them.
      gap = String.duplicate(" ", 9)

      assert [
               {nil, "  "},
               {"label", "x"},
               {nil, ^gap},
               {"bar", "█"},
               {nil, " "},
               {"bar", "█"},
               {nil, " "},
               {"track", "░"} | _
             ] =
               Enum.at(rows, 7)

      assert [{nil, _}, {"bar", "━" <> _}, {"track", "─" <> _}, {nil, _}, {"value", _} | _] =
               Enum.at(rows, 9)
    end

    test "with parts: true, the fill is blue, the track and ends grey, a full bar green" do
      {frame, _} =
        "progress-bar"
        |> Ascii.new!(options: %{values: [42, 100], style: 2}, parts: true)
        |> Ascii.frame(0.0)

      assert Frame.color_at(frame, 12, 1) == "#8b949e"
      assert Frame.color_at(frame, 13, 1) == "#58a6ff"
      assert Frame.color_at(frame, 23, 1) == "#8b949e"
      assert Frame.color_at(frame, 13, 3) == "#3fb950"
      assert Frame.color_at(frame, 2, 1) == nil
    end
  end
end
