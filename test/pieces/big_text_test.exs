defmodule AsciiArt.Pieces.BigTextTest do
  use ExUnit.Case, async: true

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.BigText,
    variants: [
      %{text: "hi world"},
      %{text: "a1 ?! ~é ß"},
      %{text: "the quick brown fox jumps"},
      %{text: ""}
    ]

  use AsciiArt.GoldenCase, slug: "big-text", piece: AsciiArt.Pieces.BigText

  alias AsciiArt.Frame
  alias AsciiArt.Pieces.BigText

  # Each cell's part and character at `t`, by {x, y}.
  defp cells(options, t \\ 0.0) do
    {frame, anim} = "big-text" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)

    for {runs, y} <- frame |> BigText.parts(anim.options) |> Enum.with_index(),
        {{name, ch}, x} <-
          runs
          |> Enum.flat_map(fn {name, text} -> Enum.map(String.codepoints(text), &{name, &1}) end)
          |> Enum.with_index(),
        into: %{},
        do: {{x, y}, {name, ch}}
  end

  defp named(cells, name), do: for({at, {^name, _ch}} <- cells, do: at) |> Enum.sort()

  describe "parts" do
    test "each letter's ink by its place in the text, glint and all" do
      # Mid-glint, so the letters are in both shades.
      cells = cells(%{text: "hi"}, 1.3)
      h = named(cells, "letter.1")
      i = named(cells, "letter.2")

      # H is twelve pixels and I five, each two cells wide.
      assert length(h) == 24
      assert length(i) == 10
      assert Enum.max(for {x, _} <- h, do: x) < Enum.min(for {x, _} <- i, do: x)
      assert for(at <- h ++ i, uniq: true, do: elem(cells[at], 1)) |> Enum.sort() == ~w(█ ▓)
    end

    test "every character counts, spaces too; one the font lacks has no cells" do
      cells = cells(%{text: "hi ~ok"})
      names = for {_at, {name, _ch}} <- cells, name, uniq: true, do: name
      assert Enum.sort(names) == ~w(letter.1 letter.2 letter.5 letter.6 shadow)
    end

    test "a character that is two capitals is both, as one letter" do
      one_s = cells(%{text: "sa"}) |> named("letter.1") |> length()
      assert one_s > 0
      assert cells(%{text: "ßa"}) |> named("letter.1") |> length() == 2 * one_s
    end

    test "the shadow is every other mark" do
      for {_at, {name, ch}} <- cells(%{text: "hello"}) do
        case name do
          "shadow" -> assert ch in ~w(║ ═ ╝ ╗ ╣ ╚ ╔ ╠ ╩ ╦ ╬)
          nil -> assert ch == " "
          "letter." <> _ -> assert ch in ~w(█ ▓ ▒)
        end
      end
    end

    test "with parts: true, the shadow grey, the letters in the ink; numbered letters in theirs" do
      cells = cells(%{})
      [{hx, hy} | _] = named(cells, "letter.1")
      [{ex, ey} | _] = named(cells, "letter.2")
      [{sx, sy} | _] = named(cells, "shadow")

      {frame, _} = "big-text" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)
      assert Frame.color_at(frame, hx, hy) == nil
      assert Frame.color_at(frame, sx, sy) == "#8b949e"

      parts = %{"letter" => "#00ff00", "letter.1" => "#ff0000"}
      {frame, _} = "big-text" |> AsciiArt.new!(parts: parts) |> AsciiArt.frame(0.0)
      assert Frame.color_at(frame, hx, hy) == "#ff0000"
      assert Frame.color_at(frame, ex, ey) == "#00ff00"
      assert Frame.color_at(frame, sx, sy) == nil
    end
  end

  test "it says the text" do
    assert AsciiArt.describe(AsciiArt.new!("big-text")) == "big text: hello"

    assert AsciiArt.describe(AsciiArt.new!("big-text", options: %{text: " hi\n  there "})) ==
             "big text: hi there"

    assert BigText.describe(%{text: "  "}) == nil
  end
end
