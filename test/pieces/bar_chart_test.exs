defmodule AsciiArt.Pieces.BarChartTest do
  use ExUnit.Case, async: true

  @months ~w(jan feb mar apr may jun jul aug sep oct nov dec)

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.BarChart,
    variants: [
      %{
        labels: @months,
        datasets: [%{name: "2026", values: Enum.map(1..12, &(&1 * 37))}],
        cols: 80
      },
      %{datasets: [%{name: "now", values: [1, 2, 3]}], labels: ["a", "b", "c"], cols: 30},
      %{datasets: [%{values: [0, 0]}], labels: ["x", "y"]},
      %{
        title: "a title long enough to run under the legend",
        labels: ["alpha", "beta"],
        datasets: [%{name: "first", values: [1, 2]}, %{name: "second", values: [9, 1]}]
      },
      %{
        datasets: [
          %{name: "requests", values: [2.5e9, 9.99e8, 1.0e9, 4.2e8, 3.3e9, 0, 1.0e9]},
          %{name: "signed", values: [-1.0e9, 5, -3, 1.0e9, 0, 0, 2]}
        ]
      }
    ]

  use AsciiArt.GoldenCase, slug: "bar-chart", piece: AsciiArt.Pieces.BarChart

  test "values past a million are drawn as given" do
    values = [2_500_000, 3_100_000, 1_900_000, 4_200_000, 3_300_000, 2_000_000, 2_800_000]
    options = %{datasets: [%{name: "requests", values: values}]}
    {frame, _} = "bar-chart" |> AsciiArt.new!(options: options) |> AsciiArt.frame(10.0)
    assert frame.text =~ "4200000"
  end

  @one %{title: "requests", labels: ["a", "b"], datasets: [%{name: "now", values: [100, 300]}]}

  defp text(anim, t), do: anim |> AsciiArt.frame(t) |> elem(0) |> Map.get(:text)

  test "one dataset stands still, its values on top of its bars" do
    anim = AsciiArt.new!("bar-chart", options: @one)
    assert text(anim, 1.0) == text(anim, 7.0)
    assert text(anim, 1.0) =~ "300"
  end

  test "new values taken up while playing ease from what was shown" do
    anim = AsciiArt.new!("bar-chart", options: @one)
    {shown, anim} = AsciiArt.frame(anim, 1.0)
    anim = AsciiArt.put_options!(anim, datasets: [%{name: "now", values: [300, 100]}])

    # The first frame after is still the old picture; then the bars move,
    # and settle on the new values.
    {first, anim} = AsciiArt.frame(anim, 1.0)
    assert first.text == shown.text
    {midway, anim} = AsciiArt.frame(anim, 1.5)

    refute midway.text in [
             shown.text,
             text(
               AsciiArt.new!("bar-chart",
                 options: %{@one | datasets: [%{name: "now", values: [300, 100]}]}
               ),
               1.0
             )
           ]

    {settled, _} = AsciiArt.frame(anim, 3.0)

    assert settled.text ==
             text(
               AsciiArt.new!("bar-chart",
                 options: %{@one | datasets: [%{name: "now", values: [300, 100]}]}
               ),
               1.0
             )
  end

  test "cols makes room for more bars" do
    {frame, _} =
      "bar-chart"
      |> AsciiArt.new!(
        options: %{
          labels: @months,
          datasets: [%{name: "x", values: Enum.to_list(1..12)}],
          cols: 80
        }
      )
      |> AsciiArt.frame(0.0)

    assert frame.cols == 80
    for m <- @months, do: assert(frame.text =~ m)
  end

  describe "in words" do
    defp told(options), do: "bar-chart" |> AsciiArt.new!(options: options) |> AsciiArt.describe()

    test "several datasets, each one's highest bar" do
      assert told(%{}) ==
               "visits by day, 3 datasets in turn: week 1, highest fri 540; " <>
                 "week 2, highest thu 560; week 3, highest fri 580"
    end

    test "one dataset, its bars, a missing value as zero, the ninth on as a count" do
      assert told(%{title: "", datasets: [%{values: [1, 2.5]}], labels: ~w(a b c)}) ==
               "bar chart: a 1, b 2.5, c 0"

      assert told(%{
               labels: Enum.map(1..10, &"d#{&1}"),
               datasets: [%{values: Enum.to_list(1..10)}]
             }) ==
               "visits by day: d1 1, d2 2, d3 3, d4 4, d5 5, d6 6, d7 7, d8 8, and 2 more"
    end

    test "past three datasets, how many more" do
      datasets = for i <- 1..5, do: %{name: "w#{i}", values: [i]}

      assert told(%{labels: ["a"], datasets: datasets}) ==
               "visits by day, 5 datasets in turn: w1, highest a 1; w2, highest a 2; " <>
                 "w3, highest a 3; and 2 more"
    end
  end

  describe "parts" do
    alias AsciiArt.Pieces.BarChart

    # The frame at the last of `times`, played in order, and its parts.
    defp parts(anim, times) do
      {frame, anim} = Enum.reduce(times, {nil, anim}, fn t, {_, a} -> AsciiArt.frame(a, t) end)
      {frame, BarChart.parts(frame, anim.options)}
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

    test "title, legend, axis, scale, grid, bars by place, values and labels" do
      p = parts(AsciiArt.new!("bar-chart"), [1.0])

      assert at(p, 2, 1) == {"title", "v"}
      assert at(p, 14, 1) == {"title", "y"}
      assert at(p, 32, 1) == {"legend.active", "["}
      assert at(p, 34, 1) == {"legend.active", "e"}
      assert at(p, 39, 1) == {"legend.active", "]"}
      assert at(p, 41, 1) == {nil, " "}
      assert at(p, 42, 1) == {"legend", "w"}
      assert at(p, 1, 4) == {"scale", "6"}
      assert at(p, 3, 16) == {"scale", "0"}
      assert at(p, 5, 4) == {"axis", "┤"}
      assert at(p, 5, 5) == {"axis", "│"}
      assert at(p, 5, 16) == {"axis", "└"}
      assert at(p, 6, 16) == {"axis", "─"}
      assert at(p, 6, 4) == {"grid", "┈"}
      assert at(p, 9, 10) == {"bar.1", "▇"}
      assert at(p, 9, 15) == {"bar.1", "█"}
      assert at(p, 16, 7) == {"bar.2", "▄"}
      assert at(p, 54, 12) == {"bar.7", "▄"}
      assert at(p, 9, 9) == {"value", "2"}
      assert at(p, 11, 9) == {"value", "2"}
      assert at(p, 53, 11) == {"value", "2"}
      assert at(p, 9, 17) == {"label", "m"}
      assert at(p, 0, 0) == {nil, " "}
    end

    test "the legend follows the dataset shown" do
      p = parts(AsciiArt.new!("bar-chart"), [2.0])
      assert at(p, 32, 1) == {nil, " "}
      assert at(p, 41, 1) == {"legend.active", "["}
      assert at(p, 42, 1) == {"legend.active", "w"}
    end

    test "a full bar's value above the plot" do
      p = parts(AsciiArt.new!("bar-chart", options: @one), [1.0])
      assert at(p, 33, 3) == {"value", "3"}
      assert at(p, 35, 3) == {"value", "0"}
      assert at(p, 33, 4) == {"bar.2", "█"}
    end

    test "bars easing down from values past the new top run over the title and legend" do
      anim = AsciiArt.new!("bar-chart", options: @one)
      {_, anim} = AsciiArt.frame(anim, 1.0)
      anim = AsciiArt.put_options!(anim, datasets: [%{name: "now", values: [1, 3]}])
      p = parts(anim, [1.0, 1.2])

      assert at(p, 20, 1) == {"title", "r"}
      assert at(p, 25, 1) == {"bar.1", "█"}
      assert at(p, 25, 0) == {"bar.1", "█"}
      assert at(p, 34, 1) == {"bar.2", "█"}
      assert at(p, 36, 1) == {"legend.active", "o"}
    end
  end
end
