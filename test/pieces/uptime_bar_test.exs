defmodule AsciiArt.Pieces.UptimeBarTest do
  use ExUnit.Case, async: true

  @api Enum.map(1..90, fn d ->
         if rem(d, 13) == 0, do: 91.0, else: if(rem(d, 7) == 0, do: 99.5, else: 100)
       end)

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.UptimeBar,
    variants: [
      %{history: [@api]},
      %{history: [@api, [100, 98.0], [50]], days: 20},
      %{history: [[], [99.99]], days: 196},
      %{services: ["just one"], history: [[100]]},
      %{services: []},
      %{
        services: ["a long service name here", "exactly twenty chars"],
        history: [[100, 98.0], [50]],
        days: 20
      }
    ]

  use AsciiArt.GoldenCase, slug: "uptime-bar", piece: AsciiArt.Pieces.UptimeBar

  defp draw(options, t \\ 2.0) do
    {frame, _} = "uptime-bar" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    frame
  end

  test "a history draws each day as given: up, degraded, out; blank before it began" do
    frame = draw(%{services: ["db"], history: [[100, 99.5, 50.0]], days: 20})
    assert frame.cols == 24
    assert Enum.join(frame.lines, "\n") =~ String.duplicate(" ", 17) <> "▌▖▁"
    assert frame.text =~ "partial outage"
    assert frame.text =~ "83.17%"
  end

  test "a history stands still; upstream's slides on" do
    assert draw(%{history: [@api, @api, @api]}, 1.0).text ==
             draw(%{history: [@api, @api, @api]}, 9.0).text

    refute draw(%{}, 1.0).text == draw(%{}, 9.0).text
  end

  describe "in words" do
    defp told(options),
      do: "uptime-bar" |> AsciiArt.new!(options: options) |> AsciiArt.describe()

    test "each service given a history: today's state, and its uptime over the days shown" do
      assert told(%{history: [[100, 99.9, 99.99], [], [96]]}) ==
               "uptime: api operational, 99.96% over 3 days; database outage, 96.00% over 1 day"

      assert told(%{
               history: [List.duplicate(100, 30) ++ [90]],
               days: 20
             }) ==
               "uptime: api outage, 99.50% over 20 days"
    end

    test "without a history, what the piece is" do
      assert told(%{services: ["web"]}) =~ "uptime bar: 60-day"
    end
  end

  describe "parts" do
    alias AsciiArt.Frame
    alias AsciiArt.Kit.Text
    alias AsciiArt.Pieces.UptimeBar

    defp parts(options, t \\ 0.0) do
      {frame, anim} = "uptime-bar" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
      {frame, UptimeBar.parts(frame, anim.options)}
    end

    # The part of row y's cell at column x.
    defp part_at(rows, x, y) do
      rows
      |> Enum.at(y)
      |> Enum.flat_map(fn {name, text} -> List.duplicate(name, Text.length(text)) end)
      |> Enum.at(x)
    end

    test "the headline, a service's name and state, its days, and its uptime" do
      {frame, rows} = parts(%{})

      assert [{nil, "  "}, {"title.ok", "all systems operational"}, {nil, _}] = Enum.at(rows, 1)

      assert [{nil, "  "}, {"label", "api"}, {nil, _}, {"status.ok", "operational"}, {nil, "  "}] =
               Enum.at(rows, 3)

      assert Enum.at(frame.lines, 4) |> String.slice(2, 4) == "▌▌▖▌"
      assert part_at(rows, 3, 4) == "day.up"
      assert part_at(rows, 4, 4) == "day.degraded"
      down = frame.lines |> Enum.at(4) |> String.graphemes() |> Enum.find_index(&(&1 == "▁"))
      assert part_at(rows, down, 4) == "day.down"
      assert part_at(rows, 1, 4) == nil

      assert Enum.at(rows, 5) == [
               {nil, "  "},
               {"scale", "60 days ago"},
               {nil, " "},
               {"rule", String.duplicate("·", 13)},
               {nil, " "},
               {"value", "99.82%"},
               {nil, " "},
               {"label", "uptime"},
               {nil, " "},
               {"rule", String.duplicate("·", 14)},
               {nil, " "},
               {"scale", "today"},
               {nil, "  "}
             ]
    end

    test "mid-slide, days drawn a half cell along keep their states" do
      {frame, rows} = parts(%{}, 0.6)
      assert Enum.at(frame.lines, 4) |> String.slice(2, 3) == "▐▗▐"
      assert part_at(rows, 2, 4) == "day.up"
      assert part_at(rows, 3, 4) == "day.degraded"
    end

    test "a degraded day and an outage, in the headline and the services" do
      {_frame, rows} = parts(%{}, 0.9)
      assert [{nil, "  "}, {"title.warn", "degraded performance"}, {nil, _}] = Enum.at(rows, 1)
      assert [_, {"label", "website"}, _, {"status.warn", "degraded"}, _] = Enum.at(rows, 7)

      {_frame, rows} = parts(%{services: ["db"], history: [[100, 50]]})
      assert [{nil, "  "}, {"title.fail", "partial outage"}, {nil, _}] = Enum.at(rows, 5)
      assert [_, {"label", "db"}, _, {"status.fail", "outage"}, _] = Enum.at(rows, 7)
      assert [{nil, _}, {"day.up", "▌"}, {"day.down", "▁"}, {nil, "  "}] = Enum.at(rows, 8)
    end

    test "names and states cut at the frame's edge: a state left nil when the cut is ambiguous" do
      options = %{
        services: ["api", "a long service name here", "dbase is here now x"],
        history: [[100, 98.0], [50], [99.99]],
        days: 20
      }

      {frame, rows} = parts(options)
      assert Enum.at(frame.lines, 7) == "  a long service name he"
      assert Enum.at(rows, 7) == [{nil, "  "}, {"label", "a long service name he"}]
      assert Enum.at(frame.lines, 11) == "  dbase is here now x op"

      assert [_, {"label", "dbase is here now x"}, {nil, " "}, {"status.ok", "op"}] =
               Enum.at(rows, 11)

      assert [
               {nil, "  "},
               {"scale", "20 days ago"},
               {nil, "  "},
               {"value", "99.00%"},
               {nil, " up"}
             ] =
               Enum.at(rows, 5)

      # "o" could be "operational" or "outage".
      {frame, rows} = parts(%{options | services: ["api", "exactly twenty chars"]})
      # Two services sit lower in the frame: the second's name is on row 9.
      assert Enum.at(frame.lines, 9) == "  exactly twenty chars o"
      assert Enum.at(rows, 9) == [{nil, "  "}, {"label", "exactly twenty chars"}, {nil, " o"}]
    end

    test "with parts: true, up days green, degraded yellow, down red, the scale grey" do
      {frame, _} = "uptime-bar" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)

      assert Frame.color_at(frame, 2, 1) == "#3fb950"
      assert Frame.color_at(frame, 2, 3) == nil
      assert Frame.color_at(frame, 3, 4) == "#3fb950"
      assert Frame.color_at(frame, 4, 4) == "#d29922"
      assert Frame.color_at(frame, 2, 5) == "#8b949e"
      assert Frame.color_at(frame, 51, 3) == "#3fb950"
    end
  end
end
