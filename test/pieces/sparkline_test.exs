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
      %{rows: 17.5, cols: 120.0}
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
end
