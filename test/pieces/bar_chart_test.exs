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
      %{datasets: [%{values: [0, 0]}], labels: ["x", "y"]}
    ]

  use AsciiArt.GoldenCase, slug: "bar-chart", piece: AsciiArt.Pieces.BarChart

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
end
