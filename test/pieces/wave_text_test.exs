defmodule AsciiArt.Pieces.WaveTextTest do
  use ExUnit.Case, async: true

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.WaveText,
    variants: [
      %{text: "hi there", spacing: 1},
      %{text: "a much longer line of text than fits the frame"},
      %{text: "a·b · c", amp: 2},
      %{text: "  "},
      %{settle: false, amp: 2}
    ]

  use AsciiArt.GoldenCase, slug: "wave-text", piece: AsciiArt.Pieces.WaveText

  alias AsciiArt.Frame
  alias AsciiArt.Pieces.WaveText

  # Each mark's part and character at `t`, by {x, y}.
  defp marks(options, t) do
    {frame, anim} = "wave-text" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)

    for {runs, y} <- frame |> WaveText.parts(anim.options) |> Enum.with_index(),
        {{name, ch}, x} <-
          runs
          |> Enum.flat_map(fn {name, text} -> Enum.map(String.codepoints(text), &{name, &1}) end)
          |> Enum.with_index(),
        ch != " ",
        into: %{},
        do: {{x, y}, {name, ch}}
  end

  describe "parts" do
    test "mid-swell, each letter where the swell has carried it, the dots it left the trail" do
      marks = marks(%{}, 1.5)

      # "making waves": every letter once, the space none.
      letters =
        for {{_x, y}, {"letter." <> n, ch}} <- marks, do: {String.to_integer(n), {ch, y}}

      assert letters |> Enum.map(&elem(&1, 0)) |> Enum.sort() == Enum.to_list(1..12) -- [7]

      for {n, {ch, _y}} <- letters, do: assert(ch == String.at("making waves", n - 1))
      # Lifted, sunk and level.
      assert letters |> Enum.map(fn {_n, {_ch, y}} -> y end) |> Enum.uniq() |> length() == 3

      trails = for {{_x, y}, {"trail", ch}} <- marks, do: {ch, y}
      assert trails != []
      for {ch, y} <- trails, do: assert({ch, y} == {"·", 2})
    end

    test "a letter that is a dot is a letter, lifted or level" do
      for t <- [0.0, 0.5, 1.0, 1.5, 2.0] do
        names = for {{_x, _y}, {name, "·"}} <- marks(%{text: "·a·"}, t), do: name
        assert "letter.1" in names and "letter.3" in names, "at #{t}: #{inspect(names)}"
      end
    end

    test "with parts: true the trail is grey; numbered letters take theirs" do
      marks = marks(%{}, 1.5)
      {frame, _} = "wave-text" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(1.5)

      for {{x, y}, {name, _ch}} <- marks do
        assert Frame.color_at(frame, x, y) == if(name == "trail", do: "#8b949e")
      end

      parts = %{"letter.1" => "#ff0000", "trail" => "#00ff00"}
      {frame, _} = "wave-text" |> AsciiArt.new!(parts: parts) |> AsciiArt.frame(1.5)

      for {{x, y}, {name, _ch}} <- marks do
        want =
          case name do
            "letter.1" -> "#ff0000"
            "trail" -> "#00ff00"
            _ -> nil
          end

        assert Frame.color_at(frame, x, y) == want
      end
    end
  end

  test "it says the text" do
    assert AsciiArt.describe(AsciiArt.new!("wave-text")) == "wave text: making waves"
    assert WaveText.describe(%{text: " "}) == nil
  end
end
