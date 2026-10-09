defmodule AsciiArt.Pieces.FormControlsTest do
  use ExUnit.Case, async: true

  # One field of every kind, and one of a kind the form does not know.
  @every [
    %{type: "text", label: "name", text: "ada"},
    %{type: "select", label: "plan", choices: ["free", "team", "pro"], choice: 1},
    %{type: "radio", label: "size", choices: ["s", "m", "l"], choice: 2},
    %{type: "checkbox", label: "notify", choices: ["mail", "sms"], checked: [false, true]},
    %{type: "checkbox", label: "terms"},
    %{type: "switch", label: "sync", on: true},
    %{type: "slider", label: "rate", value: 2.5, min: 0.0, max: 10.0, step: 0.5, unit: " /s"},
    %{type: "colour", label: "hue"}
  ]

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.FormControls,
    variants: [
      %{title: ""},
      %{title: "a title long enough to run past the right edge of the frame"},
      %{fields: @every},
      %{fields: @every, focus: 3, status: "saved", buttons: ["back", "next", "finish"]},
      %{fields: @every, focus: 9, title: ""},
      %{fields: @every, focus: -1, buttons: []},
      %{fields: @every, cols: 32},
      %{
        fields: [
          %{label: "a label far too long for its column", text: String.duplicate("long ", 50)},
          %{type: "slider", label: "odd", value: 900.0, min: 10.0, max: -10.0, step: 0.0},
          %{type: "radio", label: "none"}
        ],
        cols: 40
      }
    ]

  use AsciiArt.GoldenCase, slug: "form-controls", piece: AsciiArt.Pieces.FormControls

  describe "parts" do
    alias AsciiArt.Frame
    alias AsciiArt.Pieces.FormControls

    defp parts(t, options \\ %{}) do
      {frame, anim} = "form-controls" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
      {frame, FormControls.parts(frame, anim.options)}
    end

    # Each cell's character and part on row `y`, from column `x`, `n` of them.
    defp cells(frame, rows, x, y, n \\ 1) do
      chars = frame.lines |> Enum.at(y) |> String.codepoints() |> Enum.slice(x, n)

      names =
        rows
        |> Enum.at(y)
        |> Enum.flat_map(fn {name, text} -> List.duplicate(name, String.length(text)) end)
        |> Enum.slice(x, n)

      Enum.zip(chars, names)
    end

    defp part(frame, rows, x, y, n) do
      case frame |> cells(rows, x, y, n) |> Enum.map(&elem(&1, 1)) |> Enum.uniq() do
        [name] -> name
        names -> names
      end
    end

    test "the frame, its title, and the keys along the bottom" do
      {_frame, rows} = parts(0.0)

      assert Enum.at(rows, 0) == [
               {"frame", "╭─"},
               {nil, " "},
               {"title", "preferences"},
               {nil, " "},
               {"frame", String.duplicate("─", 38) <> "╮"}
             ]

      assert Enum.at(rows, 15) == [
               {"frame", "╰" <> String.duplicate("─", 13)},
               {nil, " "},
               {"key", "tab"},
               {"hint", " next · "},
               {"key", "space"},
               {"hint", " change · "},
               {"key", "enter"},
               {"hint", " save "},
               {"frame", "─╯"}
             ]

      assert Enum.at(rows, 1) == [
               {"frame", "│"},
               {nil, String.duplicate(" ", 52)},
               {"frame", "│"}
             ]
    end

    test "titles empty, or cut short at the right edge" do
      {_frame, rows} = parts(0.0, %{title: ""})

      assert Enum.at(rows, 0) == [
               {"frame", "╭─"},
               {nil, "  "},
               {"frame", String.duplicate("─", 49) <> "╮"}
             ]

      title = String.duplicate("t", 60)
      {frame, rows} = parts(0.0, %{title: title})
      assert Enum.at(frame.lines, 0) == "╭─ " <> String.duplicate("t", 50) <> "╮"

      assert Enum.at(rows, 0) == [
               {"frame", "╭─"},
               {nil, " "},
               {"title", String.duplicate("t", 50)},
               {"frame", "╮"}
             ]
    end

    test "the focused field: its marker, label, and the input's text and caret" do
      {frame, rows} = parts(0.0)
      assert cells(frame, rows, 2, 2) == [{">", "focus"}]
      assert part(frame, rows, 4, 2, 5) == "label.focus"
      assert cells(frame, rows, 14, 2) == [{"[", "frame.input"}]
      assert part(frame, rows, 16, 2, 16) == "field"
      assert cells(frame, rows, 32, 2) == [{"█", "cursor"}]
      assert cells(frame, rows, 49, 2) == [{"]", "frame.input"}]
      assert part(frame, rows, 4, 4, 5) == "label"
      assert part(frame, rows, 4, 12, 6) == "label"
    end

    test "the select, the radio buttons, the checkboxes, the switch and the slider" do
      {frame, rows} = parts(0.0)
      assert part(frame, rows, 16, 4, 6) == "field"
      assert cells(frame, rows, 47, 4) == [{"v", "frame.select"}]
      assert part(frame, rows, 14, 6, 3) == "checked"
      assert part(frame, rows, 18, 6, 5) == "field"

      assert cells(frame, rows, 26, 6, 3) == [
               {"(", "unchecked"},
               {" ", "unchecked"},
               {")", "unchecked"}
             ]

      assert part(frame, rows, 14, 8, 3) == "checked"
      assert part(frame, rows, 28, 8, 3) == "unchecked"
      assert part(frame, rows, 32, 8, 8) == "field"

      assert cells(frame, rows, 14, 10, 8) == [
               {"▕", "track"},
               {"█", "knob"},
               {"█", "knob"},
               {"░", "track"},
               {"░", "track"},
               {"░", "track"},
               {"░", "track"},
               {"▏", "track"}
             ]

      assert part(frame, rows, 23, 10, 3) == "field"

      assert cells(frame, rows, 25, 12, 3) == [{"━", "bar"}, {"█", "knob"}, {"─", "track"}]
      assert part(frame, rows, 14, 12, 12) == "bar"

      assert cells(frame, rows, 46, 12, 4) == [
               {" ", nil},
               {"4", "value"},
               {"0", "value"},
               {"%", "unit"}
             ]

      assert part(frame, rows, 27, 14, 10) == "button"
      assert part(frame, rows, 40, 14, 10) == "button"
    end

    test "the switch filled behind its knob" do
      {frame, rows} = parts(4.5)
      assert cells(frame, rows, 2, 10) == [{">", "focus"}]
      assert part(frame, rows, 4, 10, 4) == "label.focus"
      assert part(frame, rows, 4, 2, 5) == "label"
      assert part(frame, rows, 15, 10, 4) == "bar"
      assert part(frame, rows, 19, 10, 2) == "knob"
      assert part(frame, rows, 23, 10, 2) == "field"
      assert cells(frame, rows, 32, 2) == [{" ", nil}]
    end

    test "the select's list, open over the rows beneath" do
      {frame, rows} = parts(1.5)
      assert cells(frame, rows, 2, 4) == [{">", "focus"}]
      assert cells(frame, rows, 47, 4) == [{"^", "frame.select"}]
      assert part(frame, rows, 14, 5, 36) == "frame.menu"
      assert part(frame, rows, 14, 8, 36) == "frame.menu"
      assert cells(frame, rows, 14, 6) == [{"│", "frame.menu"}]
      assert cells(frame, rows, 49, 7) == [{"│", "frame.menu"}]
      assert part(frame, rows, 18, 6, 6) == "field"
      assert cells(frame, rows, 16, 7) == [{">", "focus"}]
      assert part(frame, rows, 18, 7, 8) == "field"
      assert part(frame, rows, 4, 6, 5) == "label"
      assert part(frame, rows, 4, 8, 6) == "label"
    end

    test "the buttons focused and pressed, then saved" do
      {frame, rows} = parts(6.5)
      assert Enum.at(frame.lines, 14) =~ ">[▒▒save▒▒]"
      assert cells(frame, rows, 39, 14) == [{">", "focus"}]
      assert part(frame, rows, 40, 14, 10) == "button.focus"
      assert part(frame, rows, 27, 14, 10) == "button"

      {frame, rows} = parts(7.0)
      assert part(frame, rows, 4, 14, 5) == "status.ok"
      assert part(frame, rows, 40, 14, 10) == "button.focus"
    end

    test "with parts: true, focus and keys yellow, the frame grey, checked green" do
      {frame, _} = "form-controls" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)
      assert Frame.color_at(frame, 2, 2) == "#d29922"
      assert Frame.color_at(frame, 0, 5) == "#8b949e"
      assert Frame.color_at(frame, 14, 2) == "#8b949e"
      assert Frame.color_at(frame, 15, 15) == "#d29922"
      assert Frame.color_at(frame, 14, 8) == "#3fb950"
      assert Frame.color_at(frame, 4, 4) == nil
    end
  end

  describe "a form of the app's own" do
    alias AsciiArt.Frame
    alias AsciiArt.Pieces.FormControls

    # Upstream's own form as fields, as frame 0 of its tour has them.
    @tour [
      %{type: "text", label: "email", text: "team@example.com"},
      %{type: "select", label: "units", choices: ["metric", "imperial"]},
      %{type: "radio", label: "theme", choices: ["light", "dark", "system"]},
      %{type: "checkbox", label: "notify", choices: ["replies", "mentions"], checked: [true]},
      %{type: "switch", label: "sync"},
      %{type: "slider", label: "volume", value: 40, unit: "%"}
    ]

    defp form(options, t \\ 0.0),
      do: "form-controls" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)

    defp lines(options), do: elem(form(options), 0).lines

    defp press(anim, keys) do
      Enum.reduce(keys, anim, fn key, anim ->
        {:ok, anim} = AsciiArt.handle_event(anim, {:key, key})
        anim
      end)
    end

    defp click(anim, x, y), do: AsciiArt.handle_event(anim, {:click, x, y})

    defp field(anim, i), do: Enum.at(anim.options.fields, i)

    test "each control drawn as upstream draws it, row for row; the keys say what they do" do
      ours = lines(%{fields: @tour})
      assert Enum.take(ours, 15) == Enum.take(lines(%{}), 15)

      assert List.last(ours) ==
               "╰" <> String.duplicate("─", 15) <> " tab next · space change · enter ok ─╯"
    end

    test "every kind, a kind it does not know as its label alone" do
      lines = lines(%{fields: @every})
      assert Enum.at(lines, 2) == "│ > name      [ ada█" <> String.duplicate(" ", 29) <> "]   │"
      assert Enum.at(lines, 4) == "│   plan      [ team" <> String.duplicate(" ", 27) <> "v ]   │"

      assert Enum.at(lines, 6) ==
               "│   size      ( ) s   ( ) m   (*) l" <> String.duplicate(" ", 18) <> "│"

      assert Enum.at(lines, 8) ==
               "│   notify    [ ] mail   [x] sms" <> String.duplicate(" ", 21) <> "│"

      assert Enum.at(lines, 10) == "│   terms     [ ]" <> String.duplicate(" ", 36) <> "│"
      assert Enum.at(lines, 12) == "│   sync      ▕▒▒▒▒██▏ on" <> String.duplicate(" ", 28) <> "│"

      assert Enum.at(lines, 14) ==
               "│   rate      ━━━━━━━█" <> String.duplicate("─", 20) <> "  2.5 /s   │"

      assert Enum.at(lines, 16) == "│   hue" <> String.duplicate(" ", 46) <> "│"
    end

    test "its rows follow the fields, two a field; its width is cols" do
      {frame, anim} = form(%{fields: @every})
      assert {frame.cols, frame.rows} == {54, 20}
      assert {anim.cols, anim.rows} == {54, 20}

      {frame, _} = form(%{fields: Enum.take(@every, 2), cols: 80})
      assert {frame.cols, frame.rows} == {80, 8}
      assert frame.lines |> Enum.at(2) |> String.ends_with?("]   │")
    end

    test "narrow, the controls are cut at the edge, the keys shortened, buttons that do not fit dropped" do
      lines = lines(%{fields: @every, cols: 32, buttons: ["one", "two", "three"]})
      assert Enum.at(lines, 6) == "│   size      ( ) s   ( ) m    │"
      assert Enum.at(lines, 14) == "│   rate      ━█────  2.5 /s   │"
      assert Enum.at(lines, 18) == "│    [  two   ]   [ three  ]   │"
      assert List.last(lines) == "╰──── tab next · space change ─╯"
    end

    test "the focus marks its field, a row of checkboxes the one keys tick, or a button" do
      assert lines(%{fields: @every, focus: 3}) |> Enum.at(8) =~
               "│ > notify   >[ ] mail   [x] sms"

      lines =
        lines(%{fields: @every, focus: 9, status: "saved", buttons: ["back", "next", "finish"]})

      assert Enum.at(lines, 2) =~ "│   name      [ ada  "
      assert Enum.at(lines, 18) == "│   saved     [  back  ]  >[  next  ]   [ finish ]   │"

      assert lines(%{fields: @every, focus: -1}) |> Enum.at(2) =~ "│   name      [ ada  "
    end

    test "a text field shows the end of its text in focus, so the caret shows; its start out of it" do
      text = String.duplicate("abcdefghij", 5)
      fields = [%{label: "note", text: text}]

      assert lines(%{fields: fields}) |> Enum.at(2) =~
               "[ " <> String.slice(text, -31, 31) <> "█ ]"

      assert lines(%{fields: fields, focus: -1}) |> Enum.at(2) =~
               "[ " <> String.slice(text, 0, 32) <> " ]"
    end

    test "the caret holds, then blinks, and holds again while keys come" do
      caret = fn frame -> frame.lines |> Enum.at(2) |> String.contains?("ada█") end
      {at_0, anim} = form(%{fields: @every})
      {at_half, anim} = AsciiArt.frame(anim, 0.5)
      {at_1, anim} = AsciiArt.frame(anim, 1.0)
      assert {caret.(at_0), caret.(at_half), caret.(at_1)} == {true, false, true}

      {typed, _anim} = anim |> press(["backspace"]) |> AsciiArt.frame(1.5)
      assert typed.lines |> Enum.at(2) |> String.contains?("ad█")
    end

    test "tab, back tab, up, down, home, end and enter move the focus" do
      # Eight fields, then the two buttons.
      {_frame, anim} = form(%{fields: @every})
      assert press(anim, ["tab"]).options.focus == 1
      assert press(anim, ["back_tab"]).options.focus == 9
      assert press(anim, List.duplicate("tab", 10)).options.focus == 0
      assert press(anim, ["up"]).options.focus == 0
      assert press(anim, ["end", "down"]).options.focus == 9
      assert press(anim, ["down", "home"]).options.focus == 0
      assert press(anim, ["enter"]).options.focus == 1

      {_frame, none} = form(%{fields: @every, focus: -1})
      assert press(none, ["tab"]).options.focus == 0
      assert press(none, ["up"]).options.focus == 9
    end

    test "on a button, left and right move along the buttons; pressing one is the app's" do
      {_frame, anim} = form(%{fields: @every, focus: 9})
      assert press(anim, ["left"]).options.focus == 8
      assert press(anim, ["left", "left"]).options.focus == 8
      assert press(anim, ["left", "right"]).options.focus == 9
      assert AsciiArt.handle_event(anim, {:key, "enter"}) == :ignore
      assert AsciiArt.handle_event(anim, {:key, " "}) == :ignore
    end

    test "typing into a text field, printable characters up to 256, backspace taking one off" do
      {_frame, anim} = form(%{fields: @every})
      assert field(press(anim, ["!", " ", "d", "backspace"]), 0).text == "ada! "
      assert AsciiArt.handle_event(anim, {:key, "é"}) == :ignore

      {_frame, full} = form(%{fields: [%{label: "note", text: String.duplicate("x", 256)}]})
      assert AsciiArt.handle_event(full, {:key, "y"}) == :ignore
    end

    test "space and the arrows change the field in focus, the rest of it as given" do
      {_frame, anim} = form(%{fields: @every})
      to = fn i -> press(anim, List.duplicate("tab", i)) end

      plan = to.(1)
      assert field(press(plan, [" "]), 1).choice == 2
      assert field(press(plan, [" ", " "]), 1).choice == 0
      assert field(press(plan, ["left"]), 1).choice == 0
      assert field(press(plan, ["right", "right"]), 1).choice == 2

      assert field(press(to.(2), ["left"]), 2).choice == 1

      notify = to.(3)
      assert field(press(notify, [" "]), 3).checked == [true, true]

      assert field(press(notify, ["right", " "]), 3) |> Map.take([:checked, :choice]) ==
               %{checked: [false, false], choice: 1}

      assert field(press(to.(4), [" "]), 4) ==
               %{type: "checkbox", label: "terms", checked: [true], choice: 0}

      sync = to.(5)
      assert field(press(sync, [" "]), 5) == %{type: "switch", label: "sync", on: false}
      assert field(press(sync, ["left", "right"]), 5).on == true

      rate = to.(6)
      assert field(press(rate, ["right"]), 6).value == 3.0
      assert field(press(rate, List.duplicate("left", 6)), 6).value == 0.0
      assert field(press(rate, ["page_up"]), 6).value == 7.5
      assert field(press(rate, ["page_up", "page_up"]), 6).value == 10.0

      {frame, _anim} = rate |> press(["right"]) |> AsciiArt.frame(1.0)
      assert Enum.at(frame.lines, 14) =~ "━━━━━━━━█" <> String.duplicate("─", 19) <> "  3.0 /s"
    end

    test "a click takes the focus to its field, and picks, ticks, flips or sets what it lands on" do
      {_frame, anim} = form(%{fields: @every})

      {:ok, clicked} = click(anim, 5, 4)
      assert clicked.options.focus == 1
      assert clicked.options.fields == @every

      {:ok, clicked} = click(anim, 23, 6)
      assert {clicked.options.focus, field(clicked, 2).choice} == {2, 1}

      {:ok, clicked} = click(anim, 26, 8)

      assert field(clicked, 3) |> Map.take([:checked, :choice]) == %{
               checked: [false, false],
               choice: 1
             }

      {:ok, clicked} = click(anim, 14, 10)
      assert field(clicked, 4).checked == [true]

      {:ok, clicked} = click(anim, 15, 12)
      assert field(clicked, 5).on == false

      # The track is 28 cells from column 14, 0 to 10 by halves.
      assert {:ok, %{options: %{fields: fields}}} = click(anim, 14, 14)
      assert Enum.at(fields, 6).value == 0.0
      assert {:ok, %{options: %{fields: fields}}} = click(anim, 41, 14)
      assert Enum.at(fields, 6).value == 10.0
      assert {:ok, %{options: %{fields: fields}}} = click(anim, 23, 14)
      assert Enum.at(fields, 6).value == 3.5
    end

    test "a click on a select in focus steps it on; on a button focuses it; elsewhere nothing" do
      {_frame, anim} = form(%{fields: @every})
      {:ok, focused} = click(anim, 20, 4)
      assert field(focused, 1).choice == 1
      {:ok, stepped} = click(focused, 20, 4)
      assert field(stepped, 1).choice == 2

      {:ok, clicked} = click(anim, 41, 18)
      assert clicked.options.focus == 9
      {:ok, clicked} = click(anim, 30, 18)
      assert clicked.options.focus == 8

      for {x, y} <- [{37, 18}, {0, 2}, {5, 1}, {5, 19}, {60, 2}, {5, 40}] do
        assert click(anim, x, y) == :ignore
      end
    end

    test "the demo takes no events" do
      {_frame, anim} = form(%{})
      assert AsciiArt.handle_event(anim, {:key, "tab"}) == :ignore
      assert click(anim, 20, 4) == :ignore
    end

    test "parts read from the options: labels, fields, marks, the caret, values and units" do
      {frame, anim} = form(%{fields: @every, status: "saved"})
      rows = FormControls.parts(frame, anim.options)

      assert Enum.at(rows, 2) == [
               {"frame", "│"},
               {nil, " "},
               {"focus", ">"},
               {nil, " "},
               {"label.focus", "name"},
               {nil, "      "},
               {"frame.input", "["},
               {nil, " "},
               {"field", "ada"},
               {"cursor", "█"},
               {nil, String.duplicate(" ", 29)},
               {"frame.input", "]"},
               {nil, "   "},
               {"frame", "│"}
             ]

      assert [_, _, {"label", "size"}, _, {"unchecked", "( )"}, {nil, " "}, {"field", "s"} | _] =
               Enum.at(rows, 6)

      assert {"checked", "(*)"} in Enum.at(rows, 6)
      assert {"checked", "[x]"} in Enum.at(rows, 8)

      assert Enum.slice(Enum.at(rows, 12), 4, 6) == [
               {"track", "▕"},
               {"bar", "▒▒▒▒"},
               {"knob", "██"},
               {"track", "▏"},
               {nil, " "},
               {"field", "on"}
             ]

      assert Enum.slice(Enum.at(rows, 14), 4, 7) == [
               {"bar", "━━━━━━━"},
               {"knob", "█"},
               {"track", String.duplicate("─", 20)},
               {nil, "  "},
               {"value", "2.5"},
               {nil, " "},
               {"unit", "/s"}
             ]

      assert Enum.slice(Enum.at(rows, 18), 1, 4) == [
               {nil, "   "},
               {"status", "saved"},
               {nil, String.duplicate(" ", 18)},
               {"button", "[ cancel ]"}
             ]

      assert Enum.at(rows, 19) == [
               {"frame", "╰" <> String.duplicate("─", 15)},
               {nil, " "},
               {"key", "tab"},
               {"hint", " next · "},
               {"key", "space"},
               {"hint", " change · "},
               {"key", "enter"},
               {"hint", " ok "},
               {"frame", "─╯"}
             ]
    end

    test "the caret is a part only while it shows" do
      {_at_0, anim} = form(%{fields: @every})
      {frame, anim} = AsciiArt.frame(anim, 0.5)

      refute frame
             |> FormControls.parts(anim.options)
             |> Enum.at(2)
             |> List.keymember?("cursor", 0)
    end

    test "with parts: true, the focus yellow, the marks green and grey" do
      {frame, _anim} =
        "form-controls"
        |> AsciiArt.new!(options: %{fields: @every, focus: 3}, parts: true)
        |> AsciiArt.frame(0.0)

      assert Frame.color_at(frame, 2, 8) == "#d29922"
      assert Frame.color_at(frame, 13, 8) == "#d29922"
      assert Frame.color_at(frame, 14, 8) == "#8b949e"
      assert Frame.color_at(frame, 25, 8) == "#3fb950"
      assert Frame.color_at(frame, 4, 2) == nil
    end

    test "described in words: each field and what it holds, and where the focus is" do
      assert FormControls.describe(%{fields: [], title: "preferences"}) == nil

      {_frame, anim} = form(%{fields: @every})

      assert AsciiArt.describe(anim) ==
               "preferences: name ada, plan team, size l, notify sms, terms off, sync on, " <>
                 "rate 2.5 /s, hue; focus on name"

      {_frame, anim} = form(%{fields: @tour, focus: 7, title: ""})

      assert AsciiArt.describe(anim) ==
               "form: email team@example.com, units metric, theme light, notify replies, " <>
                 "sync off, volume 40%; focus on save"

      many = for i <- 1..30, do: %{label: "field #{i}", text: "text #{i}"}
      {_frame, anim} = form(%{fields: many, focus: -1})
      told = AsciiArt.describe(anim)
      assert told =~ ~r/^preferences: field 1 text 1, field 2 text 2, .*, and \d+ more$/
      assert String.length(told) < 200
    end
  end
end
