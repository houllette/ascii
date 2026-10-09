defmodule AsciiArt.Pieces.SparklineTest do
  use ExUnit.Case, async: true

  @cpu %{label: "cpu", unit: "%", lo: 0, hi: 100, values: [10, 40, 35, 80, 60, 20, 95]}

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Sparkline,
    variants: [
      %{series: [@cpu]},
      %{series: [@cpu], rows: 3, cols: 40, range: false},
      %{series: [%{label: "load", values: Enum.map(1..300, &(&1 * 0.5))}], cols: 200},
      %{series: List.duplicate(@cpu, 5), rows: 3},
      %{series: [%{label: "empty", values: []}]},
      %{rows: 17.5, cols: 120.0},
      %{series: [%{label: "big", unit: " units", values: [123_456_789, 5]}]},
      %{series: [%{label: "bytes", unit: " b", values: [3_020_463_651, 17_500_073]}]},
      %{series: [%{label: "neg", lo: -1.0e15, hi: 1.0e15, values: [-4.2e12, -1.0e9, 0.5]}]},
      %{series: [%{label: "wide", unit: " widgets/s", digits: 2, values: [1.0e15, -1.0e15]}]}
    ]

  use AsciiArt.GoldenCase, slug: "sparkline", piece: AsciiArt.Pieces.Sparkline

  defp draw(options) do
    {frame, _} = "sparkline" |> AsciiArt.new!(options: options) |> AsciiArt.frame(1.0)
    frame
  end

  test "a series with values draws its newest, scaled to lo and hi, and its latest value" do
    frame = draw(%{series: [@cpu], rows: 3, cols: 60, range: false})
    assert {frame.cols, frame.rows} == {60, 3}
    assert Enum.at(frame.lines, 1) =~ "cpu"
    assert Enum.at(frame.lines, 1) =~ "▂▄▃▇▅▂█▏     95%"
  end

  test "rows are never fewer than the series need" do
    assert draw(%{series: List.duplicate(@cpu, 5), rows: 3}).rows == 7
  end

  test "values too wide for their columns are written to fit, the columns in line" do
    frame = draw(%{series: [%{label: "bytes", unit: " b", values: [3_020_463_651, 17_500_073]}]})
    assert Enum.at(frame.lines, 4) =~ ~r/█▁▏ 17\.5M b  17\.5M 3\.02G  $/
    assert String.length(Enum.at(frame.lines, 4)) == 72

    frame = draw(%{series: [%{label: "x", unit: "%", digits: 2, values: [1234.567, -12.345]}]})
    assert Enum.at(frame.lines, 4) =~ ~r/▏ -12\.35%  -12\.3  1235  $/
  end

  test "values past a million are taken as given" do
    frame = draw(%{series: [%{label: "big", lo: 0, hi: 4.0e12, values: [1.0e12, 3.9e12]}]})
    assert Enum.at(frame.lines, 4) =~ "▃█▏    3.9T     1T  3.9T"
  end

  test "values from params are checked: numbers only" do
    assert {:ok, _} =
             AsciiArt.new("sparkline",
               options: %{"series" => [%{"label" => "x", "values" => [1, 2]}]}
             )

    assert {:error, {:invalid_option, "series"}} =
             AsciiArt.new("sparkline", options: %{"series" => [%{"values" => ["x"]}]})
  end

  test "new samples taken up while playing" do
    anim = AsciiArt.new!("sparkline", options: %{series: [@cpu], range: false})
    anim = AsciiArt.put_options!(anim, series: [%{@cpu | values: @cpu.values ++ [5]}])
    {frame, _} = AsciiArt.frame(anim, 2.0)
    assert Enum.join(frame.lines) =~ "▁▏      5%"
  end

  describe "in words" do
    defp told(options),
      do: "sparkline" |> AsciiArt.new!(options: options) |> AsciiArt.describe()

    test "each series given values: its label and its latest value, in full" do
      series = [
        %{label: "cpu", unit: "%", values: [3, 34]},
        %{label: "memory", unit: " gb", digits: 1, values: [2.08]},
        %{label: "bytes", unit: " b", values: [3_020_463_651]},
        %{label: "requests", unit: "/s", values: []}
      ]

      assert told(%{series: series}) ==
               "sparkline: cpu 34%, memory 2.1 gb, bytes 3020463651 b, requests no samples"
    end

    test "series playing the sample signal are left out; none given, what the piece is" do
      assert told(%{series: [%{label: "sim"}, %{label: "x", values: [1]}]}) == "sparkline: x 1"
      assert told(%{}) =~ "sparkline: three live"
    end
  end

  describe "parts" do
    alias AsciiArt.Pieces.Sparkline

    # The frame at 1s and its parts.
    defp parts(options) do
      {frame, anim} = "sparkline" |> AsciiArt.new!(options: options) |> AsciiArt.frame(1.0)
      {frame, Sparkline.parts(frame, anim.options)}
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

    test "each series' label, spark, value and range; the headings and the time axis" do
      p = parts(%{})

      assert at(p, 61, 1) == {"title", "m"}
      assert at(p, 67, 1) == {"title", "m"}
      assert at(p, 2, 2) == {"label", "c"}
      assert at(p, 12, 2) == {"spark.1", "▄"}
      assert at(p, 47, 2) == {"spark.1", "▇"}
      assert at(p, 12, 4) == {"spark.2", "▃"}
      assert at(p, 12, 6) == {"spark.3", "▆"}
      assert at(p, 48, 2) == {"axis", "▏"}
      assert at(p, 54, 2) == {"value", "8"}
      assert at(p, 56, 2) == {"unit", "%"}
      assert at(p, 62, 2) == {"value.min", "1"}
      assert at(p, 69, 2) == {"value.max", "2"}
      # A unit after a space, and decimals.
      assert at(p, 52, 4) == {"value", "."}
      assert at(p, 54, 4) == {nil, " "}
      assert at(p, 55, 4) == {"unit", "g"}
      assert at(p, 61, 4) == {"value.min", "1"}
      assert at(p, 12, 7) == {"scale", "9"}
      assert at(p, 48, 7) == {"scale", "w"}
      assert at(p, 0, 0) == {nil, " "}
    end

    test "values given, a short line, no range" do
      p = parts(%{series: [@cpu], rows: 3, cols: 60, range: false})
      assert at(p, 41, 1) == {nil, " "}
      assert at(p, 42, 1) == {"spark.1", "▂"}
      assert at(p, 49, 1) == {"axis", "▏"}
      assert at(p, 55, 1) == {"value", "9"}
      assert at(p, 57, 1) == {"unit", "%"}
    end

    test "five series, a row apart" do
      p = parts(%{series: List.duplicate(@cpu, 5), rows: 3})
      for {y, n} <- Enum.with_index(1..5, 1), do: assert(at(p, 47, y) == {"spark.#{n}", "█"})
      assert at(p, 12, 6) == {"scale", "9"}
    end

    test "a range cut short at the edge, by a unit too wide for its column, is still the range" do
      p = parts(%{series: [%{label: "big", unit: " widgets/s", values: [123_456_789, 5]}]})
      {frame, _} = p
      assert Enum.at(frame.lines, 4) =~ ~r/5 widgets\/s +5  12$/
      assert at(p, 50, 4) == {"value", "5"}
      assert at(p, 52, 4) == {"unit", "w"}
      assert at(p, 67, 4) == {"value.min", "5"}
      assert at(p, 70, 4) == {"value.max", "1"}
      assert at(p, 71, 4) == {"value.max", "2"}
    end

    test "values written compactly are values, their unit after them" do
      p = parts(%{series: [%{label: "bytes", unit: " b", values: [3_020_463_651, 17_500_073]}]})
      assert at(p, 50, 4) == {"value", "1"}
      assert at(p, 54, 4) == {"value", "M"}
      assert at(p, 56, 4) == {"unit", "b"}
      assert at(p, 59, 4) == {"value.min", "1"}
      assert at(p, 69, 4) == {"value.max", "G"}
    end

    test "a unit that starts with a digit is still the unit" do
      p = parts(%{series: [%{label: "x", unit: "2x", digits: 3, values: [-5, 3]}]})
      {frame, _} = p
      assert Enum.at(frame.lines, 4) =~ "3.0002x  -5.00 3.000"
      assert at(p, 54, 4) == {"value", "0"}
      assert at(p, 55, 4) == {"unit", "2"}
      assert at(p, 59, 4) == {"value.min", "-"}
      assert at(p, 65, 4) == {"value.max", "3"}
    end

    test "a series without samples has only its label and the line's end" do
      {_, rows} = parts(%{series: [%{label: "empty", values: []}]})

      assert rows |> Enum.at(4) |> Enum.reject(&(elem(&1, 0) == nil)) ==
               [{"label", "empty"}, {"axis", "▏"}]
    end
  end
end
