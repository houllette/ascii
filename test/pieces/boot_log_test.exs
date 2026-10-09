defmodule AsciiArt.Pieces.BootLogTest do
  use ExUnit.Case, async: true

  @steps [
    %{text: "built release 1.4.2", status: "ok"},
    %{text: "disk 81% full", status: "warn"},
    %{text: "copy assets", status: "fail"},
    %{text: "migrating database", status: "busy"},
    %{text: "a plain line"},
    %{text: "an odd status", status: "maybe"}
  ]

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.BootLog,
    variants: [
      %{steps: @steps, title: "deploy web"},
      %{steps: for(i <- 1..30, do: %{text: "step #{i}", status: "ok"}), cols: 30, rows: 5},
      %{title: "setup", rows: 3},
      %{steps: [%{text: String.duplicate("x", 300), status: "busy"}], cols: 24},
      %{cols: 40, rows: 8},
      %{cols: 120, rows: 30}
    ]

  use AsciiArt.GoldenCase, slug: "boot-log", piece: AsciiArt.Pieces.BootLog

  alias AsciiArt.Frame
  alias AsciiArt.Pieces.BootLog

  defp draw(options, t \\ 0.0) do
    {frame, anim} = "boot-log" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    {frame, anim}
  end

  defp lines(options, t \\ 0.0), do: options |> draw(t) |> elem(0) |> Map.fetch!(:lines)

  describe "steps" do
    test "each a line, systemd style, under the title and its rule, the cursor after" do
      lines = lines(%{steps: @steps, title: "deploy web", cols: 40, rows: 10})

      assert Enum.map(lines, &String.trim_trailing/1) == [
               " deploy web",
               " " <> String.duplicate("─", 38),
               " [  OK  ] built release 1.4.2",
               " [ WARN ] disk 81% full",
               " [FAILED] copy assets",
               " [***   ] migrating database",
               " a plain line",
               " an odd status",
               " _",
               ""
             ]

      assert Enum.all?(lines, &(String.length(&1) == 40))
    end

    test "the newest at the bottom, older ones scrolled away under the title" do
      steps = for i <- 1..30, do: %{text: "step #{i}", status: "ok"}
      lines = lines(%{steps: steps, title: "ci", rows: 6})

      assert Enum.map(lines, &String.trim_trailing/1) == [
               " ci",
               " " <> String.duplicate("─", 62),
               " [  OK  ] step 28",
               " [  OK  ] step 29",
               " [  OK  ] step 30",
               " _"
             ]

      assert lines(%{steps: steps, rows: 3}) |> Enum.map(&String.trim_trailing/1) ==
               [" [  OK  ] step 29", " [  OK  ] step 30", " _"]
    end

    test "a busy step's stars sweep in its brackets, and the cursor blinks" do
      stars =
        for t <- [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75] do
          [_, line | _] =
            lines(%{steps: [%{text: "x", status: "ok"}, %{text: "y", status: "busy"}]}, t)

          String.slice(line, 1, 8)
        end

      assert stars == [
               "[***   ]",
               "[ ***  ]",
               "[  *** ]",
               "[   ***]",
               "[  *** ]",
               "[ ***  ]",
               "[***   ]"
             ]

      assert lines(%{steps: @steps}, 0.5) |> Enum.at(6) =~ ~r/^ _ +$/
      assert lines(%{steps: @steps}, 0.7) |> Enum.at(6) =~ ~r/^ +$/
    end

    test "new steps while playing take their place; the stars and cursor keep play time" do
      {_frame, anim} = draw(%{steps: Enum.take(@steps, 2)}, 1.0)
      anim = AsciiArt.put_options!(anim, steps: @steps)
      {frame, _anim} = AsciiArt.frame(anim, 1.3)
      assert frame.text == elem(draw(%{steps: @steps}, 1.3), 0).text
    end

    test "no steps and no title plays upstream's boot; a title alone is an empty log" do
      assert elem(draw(%{steps: []}), 0).text == elem(draw(%{}), 0).text

      assert lines(%{title: "setup", rows: 4}) |> Enum.map(&String.trim_trailing/1) ==
               [" setup", " " <> String.duplicate("─", 62), " _", ""]
    end
  end

  describe "sizes" do
    test "cols and rows, within bounds" do
      assert BootLog.size(%{cols: 80, rows: 24}) == {80, 24}
      {frame, _} = draw(%{cols: 1000, rows: 1})
      assert {frame.cols, frame.rows} == {200, 3}
    end

    test "upstream's self test laid out to the width" do
      # 1.25 s in, the self test is up; its rows end at the right margin.
      lines = lines(%{cols: 80}, 1.25)
      cpu = Enum.find(lines, &String.starts_with?(&1, " cpu"))
      assert String.length(cpu) == 80
      assert cpu =~ ~r/ ok $/
      assert Enum.find(lines, &(&1 =~ "─")) == " " <> String.duplicate("─", 78) <> " "
    end
  end

  describe "parts" do
    test "a step's status in its part, then its message" do
      {frame, anim} = draw(%{steps: @steps, title: "deploy web", cols: 40, rows: 10})
      rows = BootLog.parts(frame, anim.options)

      assert Enum.at(rows, 0) == [
               {nil, " "},
               {"title", "deploy web"},
               {nil, String.duplicate(" ", 29)}
             ]

      assert Enum.at(rows, 1) == [{nil, " "}, {"rule", String.duplicate("─", 38)}, {nil, " "}]

      assert Enum.at(rows, 4) == [
               {nil, " "},
               {"status.fail", "[FAILED]"},
               {nil, " "},
               {"message", "copy assets"},
               {nil, String.duplicate(" ", 19)}
             ]

      assert [
               {nil, " "},
               {"status.busy", "[***   ]"},
               {nil, " "},
               {"message", "migrating database"} | _
             ] =
               Enum.at(rows, 5)

      assert [{nil, " "}, {"message", "an odd status"}, {nil, _}] = Enum.at(rows, 7)
      assert [{nil, " "}, {"cursor", "_"}, {nil, _}] = Enum.at(rows, 8)
      assert Enum.at(rows, 9) == [{nil, String.duplicate(" ", 40)}]
    end

    test "a step that only looks like a status is a message" do
      {frame, anim} = draw(%{steps: [%{text: "[  OK  ] not really"}]})

      assert [{nil, " "}, {"message", "[  OK  ] not really"}, {nil, _}] =
               hd(BootLog.parts(frame, anim.options))
    end

    test "with parts: true, failures red, warnings yellow" do
      {frame, _} =
        "boot-log" |> AsciiArt.new!(options: %{steps: @steps}, parts: true) |> AsciiArt.frame(0.0)

      assert Frame.color_at(frame, 1, 2) == "#f85149"
      assert Frame.color_at(frame, 1, 1) == "#d29922"
      assert Frame.color_at(frame, 1, 0) == "#3fb950"
      assert Frame.color_at(frame, 10, 2) == nil
    end
  end

  describe "describe" do
    test "nil for upstream's boot" do
      assert BootLog.describe(BootLog.meta().options) == nil
      assert AsciiArt.describe(AsciiArt.new!("boot-log")) =~ "boot log: a self test"
    end

    test "the steps counted, a failure and a step under way named" do
      anim = AsciiArt.new!("boot-log", options: %{steps: @steps, title: "deploy web"})

      assert AsciiArt.describe(anim) ==
               "deploy web: 6 steps, 1 ok, 1 warning, 1 failed (copy assets), " <>
                 "1 running (migrating database)"

      anim =
        AsciiArt.new!("boot-log",
          options: %{steps: [%{text: "a", status: "ok"}, %{text: "b", status: "ok"}]}
        )

      assert AsciiArt.describe(anim) == "boot log: 2 steps, 2 ok"

      assert AsciiArt.describe(AsciiArt.new!("boot-log", options: %{title: "setup"})) ==
               "setup: no steps yet"
    end
  end
end
