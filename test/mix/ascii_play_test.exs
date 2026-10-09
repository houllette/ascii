defmodule Mix.Tasks.Ascii.PlayTest do
  # Writes to the group leader and reads Mix.shell: not async.
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Ascii.Render.ANSI
  alias Mix.Ascii.Terminal
  alias Mix.Tasks.Ascii.Play

  test "plays a piece in place, writing only what changes, then restores the terminal" do
    out = capture_io(fn -> Play.run(["spinners", "--seconds", "0.3"]) end)
    assert String.starts_with?(out, ANSI.hide_cursor() <> ANSI.clear())

    # Frame 0 whole, a row at a time.
    first = "spinners" |> Ascii.render!() |> String.split("\n")
    assert out =~ ANSI.move(1, 1) <> hd(first)
    assert out =~ ANSI.move(13, 1) <> List.last(first)

    # Then only changes: more moves than one frame's rows, but far less than
    # a frame each time.
    moves = length(String.split(out, "\e[")) - 1
    assert moves > 13 + 4
    assert byte_size(out) < 4 * byte_size(Enum.join(first, "\n"))

    assert String.ends_with?(out, ANSI.reset() <> ANSI.move(14, 1) <> ANSI.show_cursor())
  end

  test "colour, one ink, paper and options" do
    colour = capture_io(fn -> Play.run(["elixir", "--seconds", "0.1"]) end)
    assert colour =~ "\e[38;2;"

    mono =
      capture_io(fn -> Play.run(["elixir", "--mono", "--seconds", "0.1"]) end)

    refute mono =~ "\e[38;2;"

    typed =
      capture_io(fn ->
        Play.run([
          "typewriter",
          "--option",
          "prefix=we make ",
          "--fps",
          "5",
          "--seconds",
          "0.1"
        ])
      end)

    assert typed =~ "we make "
  end

  test "ink for a piece drawn in one ink, as the terminal can show it" do
    out = capture_io(fn -> Play.run(["big-text", "--ink", "ff8800", "--seconds", "0.1"]) end)
    assert out =~ "\e[38;2;255;136;0m"

    out =
      capture_io(fn ->
        Play.run(["big-text", "--ink", "#000,#fff", "--gradient", "vertical", "--seconds", "0.1"])
      end)

    # Top to bottom: a row of frame 0 in one grey, two sevenths of the way down.
    assert out =~ ~r/\e\[3;1H +\e\[38;2;72;72;72m[^\e]+\e\[0m/

    out =
      capture_io(fn ->
        Play.run(["big-text", "--ink", "ff8800", "--mode", "ansi256", "--seconds", "0.1"])
      end)

    assert out =~ "\e[38;5;208m"

    out =
      capture_io(fn ->
        Play.run(["big-text", "--ink", "ff8800", "--mode", "mono", "--seconds", "0.1"])
      end)

    refute out =~ "\e[38;"
  end

  test "parts as the piece suggests, and one by one over them" do
    out = capture_io(fn -> Play.run(["boot-log", "--parts", "--seconds", "0.1"]) end)
    assert out =~ "\e[38;2;63;185;80m[  OK  ]"

    out =
      capture_io(fn ->
        Play.run([
          "boot-log",
          "--parts",
          "--part",
          "status.ok=ff0000",
          "--part",
          "message=00ff00",
          "--seconds",
          "0.1"
        ])
      end)

    assert out =~ "\e[38;2;255;0;0m[  OK  ]"
    assert out =~ "\e[38;2;0;255;0mstarted"

    assert_raise Mix.Error, ~r/invalid --part "evil"/, fn ->
      Play.run(["boot-log", "--part", "evil=fff"])
    end
  end

  test "plays a piece module of this project, by its name" do
    out = capture_io(fn -> Play.run(["Ascii.TestPieces.Blink", "--seconds", "0.1"]) end)
    assert out =~ ANSI.move(1, 1) <> " * "

    out =
      capture_io(fn ->
        Play.run(["Elixir.Ascii.TestPieces.Blink", "--option", "dot=o", "--seconds", "0.1"])
      end)

    assert out =~ ANSI.move(1, 1) <> " o "
  end

  test "a module name that is not a piece is an unknown piece, and makes no atom" do
    assert_raise Mix.Error, ~r/unknown piece/, fn -> Play.run(["Enum"]) end

    name = "Ascii.NoSuchPiece#{System.unique_integer([:positive])}"
    assert_raise Mix.Error, ~r/unknown piece/, fn -> Play.run([name]) end
    assert_raise ArgumentError, fn -> String.to_existing_atom("Elixir." <> name) end
  end

  test "an unknown piece, option or mode stops with a message" do
    assert_raise Mix.Error, ~r/unknown piece/, fn -> Play.run(["nope"]) end

    assert_raise Mix.Error, ~r/invalid option "evil"/, fn ->
      Play.run(["donut", "--option", "evil=1"])
    end

    assert_raise Mix.Error, ~r/--mode/, fn ->
      Play.run(["donut", "--mode", "x"])
    end

    assert_raise Mix.Error, ~r/--ink/, fn -> Play.run(["donut", "--ink", "red"]) end

    assert_raise Mix.Error, ~r/--gradient/, fn ->
      Play.run(["donut", "--ink", "fff", "--gradient", "up"])
    end

    assert_raise Mix.Error, ~r/usage/, fn -> Play.run([]) end
  end

  describe "keys for a piece (--interactive)" do
    test "raw terminal input as keys by name" do
      assert Terminal.keys("\e[A\e[B\e[C\e[D") == ~w(up down right left)
      assert Terminal.keys("\e[H\e[F\e[1~\e[4~\eOH\eOF") == ~w(home end home end home end)
      assert Terminal.keys("\e[5~\e[6~\e[3~\e[Z") == ~w(page_up page_down delete back_tab)

      assert Terminal.keys("a Z\r\n\t\d\b") == [
               "a",
               " ",
               "Z",
               "enter",
               "enter",
               "tab",
               "backspace",
               "backspace"
             ]

      assert Terminal.keys("é") == ["é"]
    end

    test "modified arrows are arrows; an unknown sequence is no key; a lone esc is esc" do
      assert Terminal.keys("\e[1;5A") == ["up"]
      assert Terminal.keys("\e[15~x") == ["x"]
      assert Terminal.keys("\e") == ["esc"]
      assert Terminal.keys("\ex") == ["esc", "x"]
    end

    test "Ctrl-C and Ctrl-D stop it" do
      assert Terminal.keys("a\x03b") == ["a", :quit, "b"]
      assert Terminal.keys(<<4>>) == [:quit]
    end

    test "a sequence cut short waits for the rest" do
      assert Terminal.keys("\e[") == []
      assert Terminal.keys("\e[5") == []
    end

    test "is a switch the task takes" do
      out =
        capture_io(fn ->
          Play.run(["file-tree", "--option", "walk=false", "--interactive", "--seconds", "0.1"])
        end)

      assert out =~ "docs/"
    end
  end
end
