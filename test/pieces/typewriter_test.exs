defmodule Ascii.Pieces.TypewriterTest do
  use ExUnit.Case, async: true

  use Ascii.ContractCase,
    piece: Ascii.Pieces.Typewriter,
    variants: [
      %{prefix: "", phrases: ["hello, world", "a  b "]},
      %{prefix: "  $ ", phrases: ["ls -la", "▌ is a cursor"]},
      %{prefix: String.duplicate("long ", 10)}
    ]

  use Ascii.GoldenCase, slug: "typewriter", piece: Ascii.Pieces.Typewriter

  alias Ascii.Frame
  alias Ascii.Pieces.Typewriter

  # A frame at `t` with `options`, and the part of each of its cells.
  defp parts_at(t, options \\ %{}) do
    anim = Ascii.new!("typewriter", options: options)
    {frame, _} = Ascii.frame(anim, t)

    names =
      for runs <- Typewriter.parts(frame, anim.options) do
        Enum.flat_map(runs, fn {name, text} -> List.duplicate(name, String.length(text)) end)
      end

    {frame, names}
  end

  defp char_at(%Frame{lines: lines}, x, y), do: lines |> Enum.at(y) |> String.at(x)
  defp name_at(names, x, y), do: names |> Enum.at(y) |> Enum.at(x)

  # The text of row y from column x on, and the part of each of its cells.
  defp row_from(frame, names, x, y, n) do
    for x <- x..(x + n - 1), do: {char_at(frame, x, y), name_at(names, x, y)}
  end

  describe "parts" do
    test "the prefix, the phrase typed so far, and the cursor" do
      {frame, names} = parts_at(0.0)
      assert Enum.at(frame.lines, 1) |> String.trim_trailing() == "         i make small tools.▌"
      assert name_at(names, 8, 1) == nil
      assert row_from(frame, names, 9, 1, 2) == [{"i", "prefix"}, {" ", "prefix"}]
      assert {char_at(frame, 15, 1), name_at(names, 15, 1)} == {" ", "prefix"}
      assert {char_at(frame, 16, 1), name_at(names, 16, 1)} == {"s", "phrase"}
      assert {char_at(frame, 27, 1), name_at(names, 27, 1)} == {".", "phrase"}
      assert {char_at(frame, 28, 1), name_at(names, 28, 1)} == {"▌", "cursor"}
      assert name_at(names, 29, 1) == nil
      assert Enum.all?(Enum.at(names, 0) ++ Enum.at(names, 2), &is_nil/1)

      # The cursor blinks off; the phrase stays.
      {frame, names} = parts_at(0.5)
      assert {char_at(frame, 27, 1), name_at(names, 27, 1)} == {".", "phrase"}
      assert {char_at(frame, 28, 1), name_at(names, 28, 1)} == {" ", nil}

      # Half deleted, the cursor follows the text back.
      {frame, names} = parts_at(1.0)
      assert {char_at(frame, 25, 1), name_at(names, 25, 1)} == {"▌", "cursor"}
      assert {char_at(frame, 24, 1), name_at(names, 24, 1)} == {"o", "phrase"}
    end

    test "a prefix from the options is the prefix wherever it sits, spaces and all" do
      {frame, names} = parts_at(0.0, %{prefix: "  $ ", phrases: ["ls -la"]})
      # 4 + 6 + 1 columns wide, centred: from column 16.
      assert row_from(frame, names, 16, 1, 5) == [
               {" ", "prefix"},
               {" ", "prefix"},
               {"$", "prefix"},
               {" ", "prefix"},
               {"l", "phrase"}
             ]

      assert {char_at(frame, 26, 1), name_at(names, 26, 1)} == {"▌", "cursor"}

      {frame, names} = parts_at(0.0, %{prefix: "", phrases: ["hello, world"]})
      x = 15
      assert {char_at(frame, x, 1), name_at(names, x, 1)} == {"h", "phrase"}
      assert name_at(names, x - 1, 1) == nil
    end

    test "a prefix wider than the line is all there is" do
      {frame, names} = parts_at(0.0, %{prefix: String.duplicate("long ", 10)})
      assert Enum.at(frame.lines, 1) == String.slice(String.duplicate("long ", 10), 0, 44)
      assert Enum.all?(Enum.at(names, 1), &(&1 == "prefix"))
    end

    test "with parts: true, the phrase and the cursor take the suggested colours" do
      {frame, _} = "typewriter" |> Ascii.new!(parts: true) |> Ascii.frame(0.0)
      assert Frame.color_at(frame, 9, 1) == nil
      assert Frame.color_at(frame, 16, 1) == "#58a6ff"
      assert Frame.color_at(frame, 28, 1) == "#d29922"
    end
  end

  test "it says each phrase as typed after the prefix, four and a count of the rest" do
    assert Ascii.describe(Ascii.new!("typewriter")) ==
             "typewriter: i make small tools; i make quiet websites; " <>
               "i make things that last; i make notes for later"

    phrases = ~w(one two three four five six)

    assert Typewriter.describe(%{prefix: "$ ", phrases: phrases}) ==
             "typewriter: $ one; $ two; $ three; $ four; and 2 more"

    assert Typewriter.describe(%{prefix: " ", phrases: ["", " "]}) == nil
  end
end
