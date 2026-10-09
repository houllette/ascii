defmodule Ascii.FrameTest do
  use ExUnit.Case, async: true

  alias Ascii.Frame

  defp frame(lines, colors \\ nil) do
    %Frame{
      text: Enum.join(lines, "\n"),
      lines: lines,
      colors: colors,
      palette: colors && ["#000000", "#ffffff"],
      cols: lines |> hd() |> String.length(),
      rows: length(lines),
      t: 0.0
    }
  end

  describe "changes/3" do
    test "with nothing before, every row whole" do
      assert Frame.changes(nil, frame(["ab", "cd"])) == [{0, 0, "ab", nil}, {1, 0, "cd", nil}]
    end

    test "nothing, when nothing changed" do
      assert Frame.changes(frame(["ab", "cd"]), frame(["ab", "cd"])) == []
    end

    test "runs of changed cells, a gap of under four unchanged cells taken in" do
      before = frame(["..........", ".........."])
      now = frame(["x..x......", "......x..."])
      assert Frame.changes(before, now) == [{0, 0, "x..x", nil}, {1, 6, "x", nil}]

      # A gap of four splits the run.
      assert Frame.changes(before, frame(["x....x....", ".........."])) ==
               [{0, 0, "x", nil}, {0, 5, "x", nil}]
    end

    test "a cell whose colour changed counts, and a run carries its colours" do
      before = frame(["abc"], <<0, 0, 0>>)
      assert Frame.changes(before, frame(["abc"], <<0, 1, 0>>)) == [{0, 1, "b", <<1>>}]
      assert Frame.changes(before, frame(["aXc"], <<0, 0, 1>>)) == [{0, 1, "Xc", <<0, 1>>}]
    end

    test "the gap can be chosen" do
      before = frame([".........."])
      now = frame(["x.......x."])
      assert Frame.changes(before, now, gap: 8) == [{0, 0, "x.......x", nil}]
      assert Frame.changes(before, now, gap: 1) == [{0, 0, "x", nil}, {0, 8, "x", nil}]
    end

    test "cells are code points, not bytes" do
      assert Frame.changes(frame(["█░█"]), frame(["███"])) == [{0, 1, "█", nil}]
    end

    test "a frame of another size, or with colours where there were none, is redrawn whole" do
      assert Frame.changes(frame(["ab"]), frame(["ab", "cd"])) == [
               {0, 0, "ab", nil},
               {1, 0, "cd", nil}
             ]

      assert Frame.changes(frame(["ab"]), frame(["ab"], <<0, 1>>)) == [{0, 0, "ab", <<0, 1>>}]
    end

    test "a real piece: applying the changes to the frame before gives the frame" do
      anim = Ascii.new!("night-coast")
      {a, anim} = Ascii.frame(anim, 1.0)
      {b, _anim} = Ascii.frame(anim, 1.1)
      changes = Frame.changes(a, b)
      assert changes != []

      lines =
        Enum.reduce(changes, a.lines, fn {y, x, text, _}, lines ->
          List.update_at(lines, y, fn line ->
            n = length(String.codepoints(text))
            String.slice(line, 0, x) <> text <> String.slice(line, (x + n)..-1//1)
          end)
        end)

      assert lines == b.lines
    end
  end
end
