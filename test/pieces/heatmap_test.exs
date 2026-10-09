defmodule AsciiArt.Pieces.HeatmapTest do
  use ExUnit.Case, async: true

  @counts Enum.map(0..200, &max(rem(&1 * 7 + div(&1, 3), 11) - 3, 0))

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Heatmap,
    variants: [
      %{counts: @counts, date: "2026-10-07"},
      %{counts: [0, 0, 0], date: "2024-02-29", weeks: 12},
      %{counts: [5_000_000, 1], weeks: 97, unit: "requests"},
      %{counts: [1, 2, 3], date: "not a date"},
      %{unit: ""},
      %{counts: [1], weeks: 12, unit: "commits to the main branch"},
      %{
        months:
          ~w(janvier fevrier mars avril mai juin juillet aout septembre octobre novembre decembre),
        weekdays: ~w(di lundi m mercredi jeudi vendredi samedi)
      },
      %{months: ["x"], weekdays: []}
    ]

  use AsciiArt.GoldenCase, slug: "heatmap", piece: AsciiArt.Pieces.Heatmap

  defp draw(options, t \\ 1.0) do
    {frame, _} = "heatmap" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    frame
  end

  test "counts past a million are counted as given" do
    assert draw(%{counts: [3_000_000, 2_500_000]}, 0.0).text =~ "5,500,000 contributions"
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

  describe "parts" do
    alias AsciiArt.Frame
    alias AsciiArt.Pieces.Heatmap

    defp parts(options, t \\ 0.0) do
      {frame, anim} = "heatmap" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
      {frame, Heatmap.parts(frame, anim.options)}
    end

    @legend [
      {"legend", "less"},
      {nil, " "},
      {"level.0", "·"},
      {nil, " "},
      {"level.1", "░"},
      {nil, " "},
      {"level.2", "▒"},
      {nil, " "},
      {"level.3", "▓"},
      {nil, " "},
      {"level.4", "█"},
      {nil, " "},
      {"legend", "more"},
      {nil, " "}
    ]

    test "months and weekdays on the scale, each day at its level" do
      {frame, rows} = parts(%{})

      assert [{nil, "      "}, {"scale", "aug"}, {nil, "   "}, {"scale", "sep"} | _] =
               Enum.at(rows, 1)

      assert Enum.at(frame.lines, 2) |> String.slice(0, 15) == "mon   ▓ ▒ · · ░"

      assert [
               {"scale", "mon"},
               {nil, "   "},
               {"level.3", "▓"},
               {nil, " "},
               {"level.2", "▒"},
               {nil, " "},
               {"level.0", "·"},
               {nil, " "},
               {"level.0", "·"},
               {nil, " "},
               {"level.1", "░"} | _
             ] = Enum.at(rows, 2)

      assert [{nil, "      "}, {"level.1", "░"}, {nil, " "}, {"level.4", "█"} | _] =
               Enum.at(rows, 3)
    end

    test "the total, its unit, and the key, its shades at their levels" do
      {frame, rows} = parts(%{})
      assert Enum.at(frame.lines, 10) =~ "706 contributions in the last 30 weeks  less"

      assert Enum.at(rows, 10) ==
               [
                 {nil, "      "},
                 {"value", "706"},
                 {nil, " "},
                 {"unit", "contributions"},
                 {nil, " in the last 30 weeks  "}
               ] ++ @legend
    end

    test "a total in thousands, a unit of words, or a foot cut short of the key" do
      {_frame, rows} = parts(%{counts: [5_000_000, 1], weeks: 97, unit: "pull requests"})

      assert [
               {nil, _},
               {"value", "5,000,001"},
               {nil, " "},
               {"unit", "pull requests"},
               {nil, _} | key
             ] =
               Enum.at(rows, 10)

      assert key == @legend

      {frame, rows} =
        parts(%{counts: [0, 1, 2, 4], date: "2026-10-07", weeks: 12, unit: "deploys"})

      assert Enum.at(frame.lines, 10) == "      7 deploys in the last 12"

      assert Enum.at(rows, 10) == [
               {nil, "      "},
               {"value", "7"},
               {nil, " "},
               {"unit", "deploys"},
               {nil, " in the last 12"}
             ]

      {frame, rows} = parts(%{counts: [1], weeks: 12, unit: "commits to the main branch"})
      assert Enum.at(frame.lines, 10) == "      1 commits to the main br"

      assert Enum.at(rows, 10) == [
               {nil, "      "},
               {"value", "1"},
               {nil, " "},
               {"unit", "commits to the main br"}
             ]
    end

    test "with parts: true, the shades in greens, the empty days and the scale grey" do
      {frame, _} = "heatmap" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)

      assert Frame.color_at(frame, 0, 2) == "#8b949e"
      assert Frame.color_at(frame, 6, 2) == "#3fb950"
      assert Frame.color_at(frame, 8, 2) == "#26a641"
      assert Frame.color_at(frame, 10, 2) == "#8b949e"
      assert Frame.color_at(frame, 14, 2) == "#006d32"
      assert Frame.color_at(frame, 8, 3) == "#39d353"
      assert Frame.color_at(frame, 6, 10) == nil
    end
  end

  describe "names" do
    alias AsciiArt.Pieces.Heatmap

    @french ~w(janvier fevrier mars avril mai juin juillet aout septembre octobre novembre decembre)

    test "months and weekdays in another language, three letters of each" do
      days = ~w(dimanche lundi mardi mercredi jeudi vendredi samedi)
      frame = draw(%{counts: @counts, date: "2026-10-07", months: @french, weekdays: days})
      english = draw(%{counts: @counts, date: "2026-10-07"})
      assert Enum.at(english.lines, 1) =~ "apr     may"
      assert Enum.at(frame.lines, 1) =~ "avr     mai"

      assert Enum.map(Enum.slice(frame.lines, 2..8), &String.slice(&1, 0, 6)) ==
               ["lun   ", "      ", "mer   ", "      ", "ven   ", "      ", "      "]

      # The days themselves are as in English.
      assert Enum.map(Enum.slice(frame.lines, 2..8), &String.slice(&1, 6..-1//1)) ==
               Enum.map(Enum.slice(english.lines, 2..8), &String.slice(&1, 6..-1//1))
    end

    test "a list of the wrong length is English" do
      assert draw(%{months: ["x"], weekdays: ["y"]}, 0.0).text == draw(%{}, 0.0).text
    end

    test "a weekday's name is the scale, whatever its letters" do
      {frame, anim} =
        "heatmap"
        |> AsciiArt.new!(options: %{weekdays: ~w(su ·o tu ░e th fr sa), counts: [1, 2]})
        |> AsciiArt.frame(0.0)

      rows = Heatmap.parts(frame, anim.options)
      assert [{"scale", "·o"}, {nil, _} | _] = Enum.at(rows, 2)
      assert [{"scale", "░e"}, {nil, _} | _] = Enum.at(rows, 4)
    end
  end

  describe "describe/1" do
    alias AsciiArt.Pieces.Heatmap

    defp describe(options), do: Heatmap.describe(Map.merge(Heatmap.meta().options, options))

    test "nothing to tell without counts" do
      assert describe(%{}) == nil
    end

    test "the total shown and the busiest day, as the frame counts them" do
      options = %{counts: @counts, date: "2026-10-07"}
      [_, total] = Regex.run(~r/([\d,]+) contributions/, draw(options).text)
      # Wednesday the 7th: 29 whole weeks and three days.
      busiest = @counts |> Enum.take(-(29 * 7 + 3)) |> Enum.max()

      assert describe(options) ==
               "heatmap: #{total} contributions in the last 30 weeks, busiest day #{busiest}"

      assert describe(%{counts: [3_000_000, 2_500_000], unit: ""}) ==
               "heatmap: 5,500,000 in the last 30 weeks, busiest day 3000000"
    end
  end
end
