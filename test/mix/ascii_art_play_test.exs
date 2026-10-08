defmodule Mix.Tasks.AsciiArt.PlayTest do
  # Writes to the group leader and reads Mix.shell: not async.
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias AsciiArt.Render.ANSI
  alias Mix.Tasks.AsciiArt.Play

  test "plays a piece in place, writing only what changes, then restores the terminal" do
    out = capture_io(fn -> Play.run(["spinners", "--seconds", "0.3"]) end)
    assert String.starts_with?(out, ANSI.hide_cursor() <> ANSI.clear())

    # Frame 0 whole, a row at a time.
    first = "spinners" |> AsciiArt.render!() |> String.split("\n")
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

  test "plays a piece module of this project, by its name" do
    out = capture_io(fn -> Play.run(["AsciiArt.TestPieces.Blink", "--seconds", "0.1"]) end)
    assert out =~ ANSI.move(1, 1) <> " * "

    out =
      capture_io(fn ->
        Play.run(["Elixir.AsciiArt.TestPieces.Blink", "--option", "dot=o", "--seconds", "0.1"])
      end)

    assert out =~ ANSI.move(1, 1) <> " o "
  end

  test "a module name that is not a piece is an unknown piece, and makes no atom" do
    assert_raise Mix.Error, ~r/unknown piece/, fn -> Play.run(["Enum"]) end

    name = "AsciiArt.NoSuchPiece#{System.unique_integer([:positive])}"
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

    assert_raise Mix.Error, ~r/usage/, fn -> Play.run([]) end
  end
end
