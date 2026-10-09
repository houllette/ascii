defmodule AsciiArt.Pieces.TerminalTest do
  use ExUnit.Case, async: true

  @history [
    %{command: "mix test", output: ["...........", "11 tests, 0 failures"]},
    %{command: "cat todo.txt", output: ["[x] water the plants", "[ ] buy stamps"]},
    %{command: "git status"}
  ]

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Terminal,
    variants: [
      %{prompt: "[x]", title: ""},
      %{prompt: "", title: String.duplicate("t", 70)},
      %{prompt: String.duplicate("p", 60)},
      %{history: @history, cols: 40, rows: 10},
      %{history: @history, typing: true, rows: 6},
      %{history: [%{output: for(i <- 1..40, do: "log line #{i}")}], cols: 12, rows: 3},
      %{history: [%{command: String.duplicate("c", 90), output: [String.duplicate("o", 90)]}]},
      %{history: [%{output: []}], typing: true, title: "", cols: 120, rows: 30},
      %{cols: 30, rows: 8}
    ]

  use AsciiArt.GoldenCase, slug: "terminal", piece: AsciiArt.Pieces.Terminal

  alias AsciiArt.Pieces.Terminal

  defp lines(options, t \\ 0.0) do
    {frame, _anim} = "terminal" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    frame.lines
  end

  # The lines inside the border, trailing spaces trimmed.
  defp screen(lines), do: lines |> Enum.slice(1..-2//1) |> Enum.map(&inner/1)

  defp inner(line), do: line |> String.slice(2..-3//1) |> String.trim_trailing()

  # The screen's lines up to the last that holds anything.
  defp shown(lines),
    do: lines |> screen() |> Enum.reverse() |> Enum.drop_while(&(&1 == "")) |> Enum.reverse()

  describe "history" do
    test "each command after the prompt, its output under it, the prompt waiting" do
      lines = lines(%{history: @history, cols: 40, rows: 10})
      assert hd(lines) == "╭─ ~/notes " <> String.duplicate("─", 28) <> "╮"

      assert screen(lines) == [
               "~/notes $ mix test",
               "...........",
               "11 tests, 0 failures",
               "~/notes $ cat todo.txt",
               "[x] water the plants",
               "[ ] buy stamps",
               "~/notes $ git status",
               "~/notes $ █"
             ]

      # The cursor sits still, so it blinks.
      assert lines(%{history: @history, cols: 40, rows: 10}, 0.7) |> screen() |> List.last() ==
               "~/notes $"
    end

    test "output alone, as a log's tail: the newest lines, the cursor on the next" do
      log = for i <- 1..40, do: "log line #{i}"
      lines = lines(%{history: [%{output: log}], rows: 6})
      assert screen(lines) == ["log line 38", "log line 39", "log line 40", "█"]
    end

    test "long lines cut to the width" do
      lines = lines(%{history: [%{command: String.duplicate("c", 90)}], cols: 20})
      assert Enum.at(lines, 1) == "│ ~/notes $ cccccc │"
    end

    test "typed out: the prompt, keys landing, output printing, then it holds" do
      typing = %{history: @history, typing: true}
      assert screen(lines(typing, 0.0)) |> hd() == "~/notes $ █"
      assert lines(typing, 1.5) |> screen() |> hd() =~ ~r/^~\/notes \$ mi?x?█$/

      assert lines(typing, 3.0) |> screen() |> Enum.take(3) == [
               "~/notes $ mix test",
               "...........",
               "11 tests, 0 failures"
             ]

      # Done, it holds on the history as it stands, the cursor blinking.
      done = for t <- [20.0, 20.25, 20.5, 20.75, 60.0], do: lines(typing, t)
      static = lines(%{history: @history})
      unblinked = &Enum.map(&1, fn line -> String.replace(line, "█", " ") end)
      assert Enum.all?(done, &(unblinked.(&1) == unblinked.(static)))
      cursor? = &Enum.any?(&1, fn line -> line =~ "█" end)
      assert Enum.any?(done, cursor?) and not Enum.all?(done, cursor?)
    end

    test "more history while typing: what is on screen stays, the new is typed from then" do
      typing = %{history: @history, typing: true}
      {_frame, anim} = "terminal" |> AsciiArt.new!(options: typing) |> AsciiArt.frame(20.0)
      more = @history ++ [%{output: ["streaming 1", "streaming 2"]}]
      anim = AsciiArt.put_options!(anim, history: more)

      {frame, anim} = AsciiArt.frame(anim, 20.0)
      assert frame.lines |> shown() |> Enum.take(-2) == ["~/notes $ git status", "█"]

      {frame, _anim} = AsciiArt.frame(anim, 20.5)
      assert frame.lines |> shown() |> Enum.take(-3) == ["streaming 1", "streaming 2", "█"]

      # The last command's output growing prints its new lines under it.
      grown = List.update_at(@history, -1, &Map.put(&1, :output, ["on branch main"]))
      {_frame, anim} = "terminal" |> AsciiArt.new!(options: typing) |> AsciiArt.frame(20.0)
      {frame, _anim} = anim |> AsciiArt.put_options!(history: grown) |> AsciiArt.frame(20.5)

      assert frame.lines |> shown() |> Enum.take(-3) ==
               ["~/notes $ git status", "on branch main", "~/notes $ █"]
    end

    test "without history, upstream's session; sizes from cols and rows" do
      assert lines(%{history: []}) == lines(%{})
      assert Terminal.size(%{cols: 80, rows: 24}) == {80, 24}
      lines = lines(%{cols: 30, rows: 8})
      assert length(lines) == 8 and Enum.all?(lines, &(String.length(&1) == 30))
      assert List.last(lines) == "╰" <> String.duplicate("─", 28) <> "╯"
    end
  end

  describe "describe" do
    test "nil for upstream's session" do
      assert Terminal.describe(Terminal.meta().options) == nil
    end

    test "the commands, or the output, counted, the last told" do
      assert AsciiArt.describe(AsciiArt.new!("terminal", options: %{history: @history})) ==
               "terminal ~/notes: 3 commands, the last git status"

      log = %{history: [%{output: ["one", "two"]}], title: ""}

      assert AsciiArt.describe(AsciiArt.new!("terminal", options: log)) ==
               "terminal: 2 lines of output, the last: two"

      assert AsciiArt.describe(AsciiArt.new!("terminal", options: %{history: [%{output: []}]})) ==
               "terminal ~/notes: empty"
    end
  end

  describe "parts" do
    alias AsciiArt.{Frame, Parts}
    alias AsciiArt.Pieces.Terminal

    defp parts(t, options \\ %{}) do
      {frame, anim} = "terminal" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
      {frame, Terminal.parts(frame, anim.options)}
    end

    # A body row's runs inside the frame and its margins, which are in
    # the frame and in no part.
    defp inside(rows, y) do
      cells =
        rows
        |> Enum.at(y)
        |> Enum.flat_map(fn {name, text} -> for c <- String.codepoints(text), do: {name, c} end)

      assert length(cells) == 62
      assert [{"frame", "│"}, {nil, " "}] == Enum.take(cells, 2)
      assert [{nil, " "}, {"frame", "│"}] == Enum.take(cells, -2)
      cells |> Enum.slice(2, 58) |> Parts.merge()
    end

    defp spaces(n), do: String.duplicate(" ", n)

    test "the frame and its title" do
      {_frame, rows} = parts(0.0)

      assert Enum.at(rows, 0) == [
               {"frame", "╭─"},
               {nil, " "},
               {"title", "~/notes"},
               {nil, " "},
               {"frame", String.duplicate("─", 50) <> "╮"}
             ]

      assert Enum.at(rows, 17) == [{"frame", "╰" <> String.duplicate("─", 60) <> "╯"}]
    end

    test "commands after the prompt, the output they print, the cursor typing" do
      {frame, rows} = parts(0.0)
      assert Enum.at(frame.lines, 13) =~ "~/notes $ ping -c 3 █"

      assert inside(rows, 1) == [
               {"prompt", "~/notes $"},
               {nil, " "},
               {"command", "ls"},
               {nil, spaces(46)}
             ]

      assert inside(rows, 2) == [
               {"output", "drafts   ideas.txt   photos   reading.txt   todo.txt"},
               {nil, spaces(6)}
             ]

      assert [
               {"prompt", "~/notes $"},
               {nil, " "},
               {"command", ~s(echo "[ ] buy stamps" >> todo.txt)} | _
             ] =
               inside(rows, 8)

      assert inside(rows, 13) == [
               {"prompt", "~/notes $"},
               {nil, " "},
               {"command", "ping -c 3 "},
               {"cursor", "█"},
               {nil, spaces(37)}
             ]

      assert inside(rows, 14) == [{nil, spaces(58)}]
    end

    test "a todo list's done and open items" do
      {_frame, rows} = parts(0.0)

      assert inside(rows, 4) == [
               {"checked", "[x]"},
               {nil, " "},
               {"output", "water the plants"},
               {nil, spaces(38)}
             ]

      assert [{"unchecked", "[ ]"}, {nil, " "}, {"output", "fix the bike light"} | _] =
               inside(rows, 6)
    end

    test "the cursor waiting on a blank line, or after a bare prompt" do
      {_frame, rows} = parts(2.5)
      assert inside(rows, 16) == [{"cursor", "█"}, {nil, spaces(57)}]

      {_frame, rows} = parts(7.0)
      assert [{"prompt", "~/notes $"}, {nil, " "}, {"cursor", "█"}, {nil, _}] = inside(rows, 1)
    end

    test "output that starts like the prompt stays output" do
      {frame, rows} = parts(0.0, %{prompt: "[x]", title: ""})
      assert Enum.at(frame.lines, 4) =~ "│ [x] water the plants"

      assert [{"checked", "[x]"}, {nil, " "}, {"output", "water the plants"} | _] =
               inside(rows, 4)

      assert [{"prompt", "[x]"}, {nil, " "}, {"command", "ls"}, {nil, _}] = inside(rows, 1)
      assert Enum.at(rows, 0) == [{"frame", "╭" <> String.duplicate("─", 60) <> "╮"}]
    end

    test "a long title or prompt, cut short" do
      {_frame, rows} = parts(0.0, %{prompt: "", title: String.duplicate("t", 70)})

      assert Enum.at(rows, 0) == [
               {"frame", "╭─"},
               {nil, " "},
               {"title", String.duplicate("t", 56)},
               {nil, " "},
               {"frame", "─╮"}
             ]

      assert [{nil, " "}, {"command", "ls"}, {nil, _}] = inside(rows, 1)
      assert inside(rows, 2) |> hd() |> elem(0) == "output"

      {_frame, rows} = parts(0.0, %{prompt: String.duplicate("p", 60)})
      assert inside(rows, 1) == [{"prompt", String.duplicate("p", 58)}]
      assert inside(rows, 2) |> hd() |> elem(0) == "output"
    end

    test "a history's commands and output, its todo items marked" do
      {_frame, rows} = parts(0.0, %{history: @history})

      assert inside(rows, 1) == [
               {"prompt", "~/notes $"},
               {nil, " "},
               {"command", "mix test"},
               {nil, spaces(40)}
             ]

      assert inside(rows, 3) == [{"output", "11 tests, 0 failures"}, {nil, spaces(38)}]

      assert [{"unchecked", "[ ]"}, {nil, " "}, {"output", "buy stamps"} | _] = inside(rows, 6)

      assert inside(rows, 8) == [
               {"prompt", "~/notes $"},
               {nil, " "},
               {"cursor", "█"},
               {nil, spaces(47)}
             ]
    end

    test "a log's lines cut to the width are output still" do
      {_frame, rows} = parts(0.0, %{history: [%{output: [String.duplicate("o", 90)]}]})
      assert inside(rows, 1) == [{"output", String.duplicate("o", 58)}]
      assert inside(rows, 2) == [{"cursor", "█"}, {nil, spaces(57)}]
    end

    test "with parts: true, the prompt blue, the frame grey, the cursor yellow" do
      {frame, _} = "terminal" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)
      assert Frame.color_at(frame, 2, 1) == "#58a6ff"
      assert Frame.color_at(frame, 0, 0) == "#8b949e"
      assert Frame.color_at(frame, 3, 0) == nil
      assert Frame.color_at(frame, 22, 13) == "#d29922"
      assert Frame.color_at(frame, 2, 4) == "#3fb950"
      assert Frame.color_at(frame, 12, 1) == nil
    end
  end
end
