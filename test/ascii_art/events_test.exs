defmodule AsciiArt.EventsTest do
  use ExUnit.Case, async: true

  alias AsciiArt.TestPieces.Switches

  use AsciiArt.ContractCase,
    piece: Switches,
    variants: [%{on: [true, true, true], cursor: 2}]

  defp draw(anim) do
    {frame, _anim} = AsciiArt.frame(anim, 0.0)
    frame.text
  end

  describe "handle_event/2" do
    test "a key the piece takes changes its options, and what it draws" do
      anim = AsciiArt.new!(Switches)
      assert draw(anim) == ">[ ]  [x]  [ ]"

      {:ok, anim} = AsciiArt.handle_event(anim, {:key, "right"})
      assert anim.options.cursor == 1
      {:ok, anim} = AsciiArt.handle_event(anim, {:key, " "})
      assert anim.options.on == [false, false, false]
      assert draw(anim) == " [ ] >[ ]  [ ]"
    end

    test "a click, on the cell clicked" do
      {:ok, anim} = AsciiArt.handle_event(AsciiArt.new!(Switches), {:click, 11, 0})
      assert anim.options == %{on: [false, true, true], cursor: 2}
    end

    test "an event the piece has no use for, or a piece that takes none, is ignored" do
      anim = AsciiArt.new!(Switches)
      assert AsciiArt.handle_event(anim, {:key, "q"}) == :ignore
      assert AsciiArt.handle_event(anim, {:click, 4, 0}) == :ignore
      assert AsciiArt.handle_event(AsciiArt.new!("donut"), {:key, "up"}) == :ignore
    end

    test "what is not an event is ignored, never handed to the piece" do
      anim = AsciiArt.new!(Switches)

      for event <- [{:key, ""}, {:key, :left}, {:click, -1, 0}, {:click, 1.5, 0}, :left, nil] do
        assert AsciiArt.handle_event(anim, event) == :ignore
      end
    end
  end

  describe "describe/1" do
    test "a piece's own words for its options" do
      anim = AsciiArt.new!(Switches, options: %{on: [true, true, false]})
      assert AsciiArt.describe(anim) == "switches: 2 of 3 on"
    end

    test "else its name and note" do
      assert AsciiArt.describe(AsciiArt.new!("donut")) ==
               "donut: a lit torus turning on two axes, after donut.c"
    end
  end

  describe "part_at/4" do
    test "the part under a cell, and its run's text" do
      anim = AsciiArt.new!(Switches)
      {frame, anim} = AsciiArt.frame(anim, 0.0)
      assert AsciiArt.part_at(anim, frame, 0, 0) == {"cursor", ">"}
      assert AsciiArt.part_at(anim, frame, 7, 0) == {"switch.on", "[x]"}
      assert AsciiArt.part_at(anim, frame, 4, 0) == {nil, "  "}
    end

    test "nil outside the frame, or for a piece that does not know its parts" do
      anim = AsciiArt.new!(Switches)
      {frame, anim} = AsciiArt.frame(anim, 0.0)
      assert AsciiArt.part_at(anim, frame, 14, 0) == nil
      assert AsciiArt.part_at(anim, frame, 0, 1) == nil

      donut = AsciiArt.new!("donut")
      {frame, donut} = AsciiArt.frame(donut, 0.0)
      assert AsciiArt.part_at(donut, frame, 10, 10) == nil
    end
  end
end
