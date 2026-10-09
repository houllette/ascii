defmodule AsciiArt.Pieces.CalendarTest do
  use ExUnit.Case, async: true

  @french %{
    months:
      ~w(janvier fevrier mars avril mai juin juillet aout septembre octobre novembre decembre),
    weekdays: ~w(dimanche lundi mardi mercredi jeudi vendredi samedi)
  }

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Calendar,
    variants: [
      %{monday: true},
      %{time: false},
      %{monday: true, time: false},
      %{date: "2026-10-12", marks: ["2026-10-03", "2026-10-12", "2026-11-01", "nope"]},
      %{date: "2026-10", marks: ["2026-10-31"], time: false},
      %{
        date: "2026-02-28",
        marks: ["2026-02-28", "2026-02-01"],
        cols: 45,
        rows: 16,
        monday: true
      },
      Map.merge(@french, %{cols: 60, rows: 20}),
      %{date: "not a date", weekdays: ["a"], months: []},
      %{date: "9999-12-31", weekdays: ~w(s m t w t f s)},
      %{date: "0001-01", cols: 200, rows: 60}
    ]

  use AsciiArt.GoldenCase, slug: "calendar", piece: AsciiArt.Pieces.Calendar

  describe "parts" do
    alias AsciiArt.Frame
    alias AsciiArt.Pieces.Calendar

    # Saturday the 14th of March 2026: the 1st is a Sunday.
    @now ~U[2026-03-14 15:09:26Z]

    defp parts(options \\ %{}) do
      {frame, anim} =
        "calendar" |> AsciiArt.new!(options: options) |> AsciiArt.frame(0.0, now: @now)

      {frame, Calendar.parts(frame, anim.options)}
    end

    defp name_at(rows, x, y) do
      rows
      |> Enum.at(y)
      |> Enum.flat_map(fn {name, text} -> List.duplicate(name, String.length(text)) end)
      |> Enum.at(x)
    end

    # The column of `text` on row `y`.
    defp column(frame, text, y) do
      line = Enum.at(frame.lines, y)
      line |> :binary.match(text) |> elem(0) |> then(&String.length(binary_part(line, 0, &1)))
    end

    test "the month, rules, weekdays and the time line" do
      {frame, rows} = parts()
      assert Enum.at(frame.lines, 1) =~ "march 2026"
      pad = String.duplicate(" ", 11)
      assert Enum.at(rows, 1) == [{nil, pad}, {"title", "march 2026"}, {nil, pad}]

      rule = [{nil, "  "}, {"rule", String.duplicate("─", 28)}, {nil, "  "}]
      assert Enum.at(rows, 2) == rule
      assert Enum.at(rows, 10) == rule
      assert Enum.at(rows, 0) == [{nil, String.duplicate(" ", 32)}]

      assert Enum.at(rows, 11) == [
               {nil, "   "},
               {"date", "saturday 14"},
               {nil, "       "},
               {"time", "15:09:26"},
               {nil, "   "}
             ]
    end

    test "days, weekends and today, bracketed" do
      {frame, rows} = parts()

      assert Enum.at(rows, 3) |> Enum.take(4) == [
               {nil, "   "},
               {"weekday.weekend", "su"},
               {nil, "  "},
               {"weekday", "mo"}
             ]

      assert name_at(rows, column(frame, "sa", 3), 3) == "weekday.weekend"
      assert name_at(rows, column(frame, "fr", 3), 3) == "weekday"

      # The 14th is today and a Saturday: today wins, brackets and all.
      x = column(frame, "[14]", 5)
      assert for(i <- 0..3, do: name_at(rows, x + i, 5)) == List.duplicate("today", 4)
      assert name_at(rows, x - 1, 5) == nil
      assert name_at(rows, column(frame, "13", 5), 5) == "day"
      assert name_at(rows, column(frame, "15", 6) + 1, 6) == "day.weekend"
      assert name_at(rows, column(frame, "21", 6), 6) == "day.weekend"
      assert name_at(rows, column(frame, "16", 6), 6) == "day"
      # The first is a Sunday, at the left.
      assert [{nil, "    "}, {"day.weekend", "1"}, {nil, "   "}, {"day", "2"} | _] =
               Enum.at(rows, 4)
    end

    test "a one-digit today keeps its brackets together" do
      {frame, anim} =
        "calendar" |> AsciiArt.new!() |> AsciiArt.frame(0.0, now: ~U[2026-03-09 08:00:00Z])

      rows = Calendar.parts(frame, anim.options)
      x = column(frame, "[9]", 5)
      assert name_at(rows, x - 1, 5) == nil
      assert for(i <- 0..2, do: name_at(rows, x + i, 5)) == List.duplicate("today", 3)
      assert name_at(rows, column(frame, "8", 5), 5) == "day.weekend"
    end

    test "weeks starting on Monday move the weekend to the right" do
      {frame, rows} = parts(%{monday: true})
      assert name_at(rows, column(frame, "mo", 3), 3) == "weekday"
      assert name_at(rows, column(frame, "sa", 3), 3) == "weekday.weekend"
      assert name_at(rows, column(frame, "su", 3), 3) == "weekday.weekend"
      assert name_at(rows, column(frame, "13", 6), 6) == "day"
      assert name_at(rows, column(frame, "15", 6), 6) == "day.weekend"
      assert name_at(rows, column(frame, "9", 6), 6) == "day"
    end

    test "without the time, the date alone" do
      {_frame, rows} = parts(%{time: false})
      assert [{nil, "   "}, {"date", "saturday 14"}, {nil, _}] = Enum.at(rows, 11)
    end

    test "a date selected, marked days, and a wider page, labelled where they fall" do
      {frame, rows} =
        parts(%{date: "2026-10-09", marks: ["2026-10-09", "2026-10-02"], cols: 45, rows: 16})

      # Cells of five, a margin of five, a row down.
      assert Enum.at(frame.lines, 6) =~ "[9]·"
      x = column(frame, "[9]", 6)
      assert for(i <- 0..3, do: name_at(rows, x + i, 6)) == List.duplicate("selected", 4)

      assert {name_at(rows, column(frame, "2·", 5), 5), name_at(rows, column(frame, "·", 5), 5)} ==
               {"day.marked", "day.marked"}

      assert name_at(rows, column(frame, "10", 6), 6) == "day.weekend"
      assert name_at(rows, column(frame, "october", 2), 2) == "title"
      assert name_at(rows, column(frame, "fr", 4), 4) == "weekday"
      assert [{nil, "      "}, {"date", "friday 9"} | _] = Enum.at(rows, 12)
    end

    test "with parts: true, today is blue and the rules grey" do
      {frame, _} =
        "calendar" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0, now: @now)

      x = column(frame, "[14]", 5)
      assert Frame.color_at(frame, x, 5) == "#58a6ff"
      assert Frame.color_at(frame, 2, 2) == "#8b949e"
      assert Frame.color_at(frame, column(frame, "13", 5), 5) == nil
    end
  end

  describe "options" do
    alias AsciiArt.Pieces.Calendar

    @now ~U[2026-03-14 15:09:26Z]

    defp draw(options, now \\ @now) do
      {frame, _anim} =
        "calendar" |> AsciiArt.new!(options: options) |> AsciiArt.frame(0.0, now: now)

      frame
    end

    test "a date shows its month, the day bracketed and named along the bottom" do
      frame = draw(%{date: "2026-10-12"})
      assert Enum.at(frame.lines, 1) =~ "october 2026"
      assert Enum.at(frame.lines, 6) == "   11 [12] 13  14  15  16  17   "
      assert Enum.at(frame.lines, 11) == "   monday 12         15:09:26   "
      # Not today's month: the clock moves only the time.
      assert draw(%{date: "2026-10-12"}, ~U[2027-01-01 09:00:00Z]).lines |> Enum.take(11) ==
               Enum.take(frame.lines, 11)
    end

    test "a month alone, nothing selected; and what is not a date, this month" do
      frame = draw(%{date: "2026-10", time: false})
      assert Enum.at(frame.lines, 6) == "   11  12  13  14  15  16  17   "
      assert String.trim(Enum.at(frame.lines, 11)) == ""
      assert draw(%{date: "2026-13"}).text == draw(%{}).text
      assert draw(%{date: "yesterday"}).text == draw(%{}).text
    end

    test "marks after their numbers, in the month shown only" do
      frame = draw(%{date: "2026-10", marks: ["2026-10-03", "2026-10-19", "2026-11-03"]})
      assert Enum.at(frame.lines, 4) == "                    1   2   3·  "
      assert Enum.at(frame.lines, 7) == "   18  19· 20  21  22  23  24   "
      refute Enum.at(frame.lines, 8) =~ "·"
      # Bracketed, a mark needs a wider cell.
      refute Enum.at(draw(%{date: "2026-10-12", marks: ["2026-10-12"]}).lines, 6) =~ "·"
    end

    test "names in another language, two letters of each weekday" do
      frame = draw(Map.put(@french, :monday, true))
      assert Enum.at(frame.lines, 1) =~ "mars 2026"
      assert Enum.at(frame.lines, 3) == "   lu  ma  me  je  ve  sa  di   "
      assert Enum.at(frame.lines, 11) =~ "samedi 14"
      # A list of the wrong length is English.
      assert draw(%{months: ["x"], weekdays: ["y"]}).text == draw(%{}).text
    end

    test "a bigger frame widens the cells and centres the page" do
      anim = AsciiArt.new!("calendar", options: %{cols: 45, rows: 16})
      assert {anim.cols, anim.rows} == {45, 16}
      frame = draw(%{cols: 45, rows: 16})
      assert Enum.at(frame.lines, 0) == String.duplicate(" ", 45)
      assert Enum.at(frame.lines, 4) == "      su   mo   tu   we   th   fr   sa       "
      assert Enum.at(frame.lines, 3) == "     " <> String.duplicate("─", 35) <> "     "
    end

    defp key(options, key),
      do: Calendar.handle_event({:key, key}, Map.merge(meta_defaults(), options))

    defp meta_defaults, do: Calendar.meta().options

    defp date_after(date, key) do
      {:ok, %{date: date}} = key(%{date: date}, key)
      date
    end

    test "keys move the date a day, a week, a month, or to the month's ends" do
      assert date_after("2026-10-12", "left") == "2026-10-11"
      assert date_after("2026-10-12", "right") == "2026-10-13"
      assert date_after("2026-10-12", "up") == "2026-10-05"
      assert date_after("2026-10-31", "down") == "2026-11-07"
      assert date_after("2026-01-31", "page_down") == "2026-02-28"
      assert date_after("2026-03-01", "page_up") == "2026-02-01"
      assert date_after("2026-10-12", "home") == "2026-10-01"
      assert date_after("2026-02-12", "end") == "2026-02-28"

      assert key(%{date: "9999-12-31"}, "right") == :ignore
    end

    test "from a month, a key selects a day of it, or moves the month" do
      assert date_after("2026-10", "down") == "2026-10-01"
      assert date_after("2026-10", "end") == "2026-10-31"
      assert date_after("2026-10", "page_down") == "2026-11"
      assert date_after("2026-01", "page_up") == "2025-12"
    end

    test "a click selects the day clicked; without a date, nothing moves" do
      frame = draw(%{date: "2026-10-12"})
      options = Map.merge(meta_defaults(), %{date: "2026-10-12"})
      x = column(frame, "19", 7)

      assert Calendar.handle_event({:click, x, 7}, options) ==
               {:ok, %{options | date: "2026-10-19"}}

      assert Calendar.handle_event({:click, 1, 7}, options) == :ignore
      assert Calendar.handle_event({:click, 3, 4}, options) == :ignore
      assert Calendar.handle_event({:click, x, 1}, options) == :ignore

      assert key(%{}, "left") == :ignore
      assert Calendar.handle_event({:click, x, 7}, meta_defaults()) == :ignore
      assert key(%{date: "2026-10-12"}, "enter") == :ignore
    end

    test "a click on a wider page, a week starting on monday" do
      options = Map.merge(meta_defaults(), %{date: "2026-10", cols: 45, rows: 16, monday: true})
      frame = draw(options)
      # The page one row down, the 26th on its last week.
      x = column(frame, "26", 9)
      assert {:ok, %{date: "2026-10-26"}} = Calendar.handle_event({:click, x + 1, 9}, options)
    end

    test "in words: the month, the day selected and the days marked in it" do
      describe = &Calendar.describe(Map.merge(meta_defaults(), &1))
      assert describe.(%{}) == nil

      assert describe.(%{date: "2026-10-12", marks: ["2026-10-24", "2026-10-03", "2026-11-01"]}) ==
               "calendar: october 2026, 12 selected, marked 3 and 24"

      assert describe.(Map.put(@french, :date, "2026-10")) == "calendar: octobre 2026"

      marks = for d <- 1..10, do: "2026-10-#{String.pad_leading("#{d}", 2, "0")}"

      assert describe.(%{date: "2026-10", marks: marks}) ==
               "calendar: october 2026, marked 1, 2, 3, 4, 5, 6, 7, 8 and 2 more"
    end
  end
end
