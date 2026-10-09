defmodule Ascii.EventsTest do
  use ExUnit.Case, async: true

  alias Ascii.TestPieces.Switches

  use Ascii.ContractCase,
    piece: Switches,
    variants: [%{on: [true, true, true], cursor: 2}]

  defp draw(anim) do
    {frame, _anim} = Ascii.frame(anim, 0.0)
    frame.text
  end

  describe "handle_event/2" do
    test "a key the piece takes changes its options, and what it draws" do
      anim = Ascii.new!(Switches)
      assert draw(anim) == ">[ ]  [x]  [ ]"

      {:ok, anim} = Ascii.handle_event(anim, {:key, "right"})
      assert anim.options.cursor == 1
      {:ok, anim} = Ascii.handle_event(anim, {:key, " "})
      assert anim.options.on == [false, false, false]
      assert draw(anim) == " [ ] >[ ]  [ ]"
    end

    test "a click, on the cell clicked" do
      {:ok, anim} = Ascii.handle_event(Ascii.new!(Switches), {:click, 11, 0})
      assert anim.options == %{on: [false, true, true], cursor: 2}
    end

    test "an event the piece has no use for, or a piece that takes none, is ignored" do
      anim = Ascii.new!(Switches)
      assert Ascii.handle_event(anim, {:key, "q"}) == :ignore
      assert Ascii.handle_event(anim, {:click, 4, 0}) == :ignore
      assert Ascii.handle_event(Ascii.new!("donut"), {:key, "up"}) == :ignore
    end

    test "what is not an event is ignored, never handed to the piece" do
      anim = Ascii.new!(Switches)

      for event <- [{:key, ""}, {:key, :left}, {:click, -1, 0}, {:click, 1.5, 0}, :left, nil] do
        assert Ascii.handle_event(anim, event) == :ignore
      end
    end
  end

  describe "describe/1" do
    test "a piece's own words for its options" do
      anim = Ascii.new!(Switches, options: %{on: [true, true, false]})
      assert Ascii.describe(anim) == "switches: 2 of 3 on"
    end

    test "else its name and note" do
      assert Ascii.describe(Ascii.new!("donut")) ==
               "donut: a lit torus turning on two axes, after donut.c"
    end
  end

  describe "part_at/4" do
    test "the part under a cell, and its run's text" do
      anim = Ascii.new!(Switches)
      {frame, anim} = Ascii.frame(anim, 0.0)
      assert Ascii.part_at(anim, frame, 0, 0) == {"cursor", ">"}
      assert Ascii.part_at(anim, frame, 7, 0) == {"switch.on", "[x]"}
      assert Ascii.part_at(anim, frame, 4, 0) == {nil, "  "}
    end

    test "nil outside the frame, or for a piece that does not know its parts" do
      anim = Ascii.new!(Switches)
      {frame, anim} = Ascii.frame(anim, 0.0)
      assert Ascii.part_at(anim, frame, 14, 0) == nil
      assert Ascii.part_at(anim, frame, 0, 1) == nil

      donut = Ascii.new!("donut")
      {frame, donut} = Ascii.frame(donut, 0.0)
      assert Ascii.part_at(donut, frame, 10, 10) == nil
    end
  end
end
