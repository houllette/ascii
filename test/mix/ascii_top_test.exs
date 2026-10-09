defmodule Mix.Tasks.Ascii.TopTest do
  # Writes to the group leader: not async.
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Ascii.Render.ANSI
  alias Mix.Tasks.Ascii.Top

  # The text written, without its escapes.
  defp plain(out), do: String.replace(out, ~r/\e\[[0-9;?]*[A-Za-z]/, "")

  test "this VM's schedulers, memory and history in panels, then the terminal restored" do
    out = capture_io(fn -> Top.run(["--seconds", "0.8", "--interval", "0.2"]) end)
    assert String.starts_with?(out, ANSI.hide_cursor() <> ANSI.clear())
    assert plain(out) =~ "╭─ beam ─"
    assert out =~ "the last two minutes"
    assert plain(out) =~ "Mem["
    assert plain(out) =~ "run queue"
    # Its own processes, not the piece's made-up ones.
    refute plain(out) =~ "indexer"
    assert out =~ "\e[38;2;"
    assert String.ends_with?(out, ANSI.show_cursor())
  end

  test "in the terminal's own colours, or a mode it can show" do
    out = capture_io(fn -> Top.run(["--seconds", "0.6", "--interval", "0.2", "--no-parts"]) end)
    assert out =~ "Mem["
    refute out =~ "\e[38;"

    out =
      capture_io(fn ->
        Top.run(["--seconds", "0.4", "--interval", "0.2", "--mode", "ansi256"])
      end)

    assert out =~ "\e[38;5;"
  end

  test "an unknown mode stops with a message" do
    assert_raise Mix.Error, ~r/--mode/, fn -> Top.run(["--mode", "sixel"]) end
  end
end
