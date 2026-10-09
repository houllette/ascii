defmodule AsciiArt.Pieces.MarqueeTest do
  use ExUnit.Case, async: true

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Marquee,
    variants: [%{text: "ok? 42% · ÿ", speed: 40}]

  use AsciiArt.GoldenCase, slug: "marquee", piece: AsciiArt.Pieces.Marquee

  alias AsciiArt.Frame
  alias AsciiArt.Pieces.Marquee

  # The part of each cell of a frame at `t`, as rows of names.
  defp parts_at(t) do
    anim = AsciiArt.new!("marquee")
    {frame, _} = AsciiArt.frame(anim, t)

    names =
      for runs <- Marquee.parts(frame, anim.options) do
        Enum.flat_map(runs, fn {name, text} -> List.duplicate(name, String.length(text)) end)
      end

    {frame, names}
  end

  defp char_at(%Frame{lines: lines}, x, y), do: lines |> Enum.at(y) |> String.at(x)
  defp name_at(names, x, y), do: names |> Enum.at(y) |> Enum.at(x)

  describe "parts" do
    test "bulbs lit and dark, by what they show" do
      {frame, names} = parts_at(0.0)
      assert {char_at(frame, 0, 0), name_at(names, 0, 0)} == {"·", "bulb.off"}
      assert {char_at(frame, 2, 0), name_at(names, 2, 0)} == {"o", "bulb.on"}
      assert {char_at(frame, 60, 1), name_at(names, 60, 1)} == {"o", "bulb.on"}
      assert {char_at(frame, 0, 3), name_at(names, 0, 3)} == {"·", "bulb.off"}
      assert name_at(names, 1, 0) == nil

      # The dark bulb walks: a moment later another bulb is the dark one.
      {frame, names} = parts_at(1.0)
      assert {char_at(frame, 0, 0), name_at(names, 0, 0)} == {"o", "bulb.on"}
      assert {char_at(frame, 2, 0), name_at(names, 2, 0)} == {"·", "bulb.off"}
    end

    test "the sign's frame, and the text's lit pixels" do
      {frame, names} = parts_at(0.0)

      for {x, y} <- [{2, 1}, {30, 1}, {58, 1}, {2, 4}, {58, 4}, {2, 8}, {58, 8}],
          do: assert(name_at(names, x, y) == "frame")

      # The panel: lit pixels are text, unlit ones in no part.
      assert {char_at(frame, 4, 4), name_at(names, 4, 4)} == {"█", "text"}
      assert {char_at(frame, 4, 3), name_at(names, 4, 3)} == {"▄", "text"}
      assert {char_at(frame, 5, 4), name_at(names, 5, 4)} == {"▄", "text"}
      assert {char_at(frame, 5, 3), name_at(names, 5, 3)} == {" ", nil}
      assert name_at(names, 30, 2) == nil
    end

    test "with parts: true, the bulbs take the colours the piece suggests" do
      {frame, _} = "marquee" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)
      assert Frame.color_at(frame, 2, 0) == "#d29922"
      assert Frame.color_at(frame, 0, 0) == "#8b949e"
      assert Frame.color_at(frame, 2, 1) == "#8b949e"
      assert Frame.color_at(frame, 4, 4) == nil
    end
  end

  test "it says the text, the dots between messages read as commas" do
    assert AsciiArt.describe(AsciiArt.new!("marquee")) ==
             "marquee: now showing, doors open at 7:30"

    assert Marquee.describe(%{text: "· sale · today only ·", speed: 12}) ==
             "marquee: sale, today only"

    assert Marquee.describe(%{text: " · ", speed: 12}) == nil
  end
end
