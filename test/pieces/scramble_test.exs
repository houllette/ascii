defmodule AsciiArt.Pieces.ScrambleTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Scramble
  use AsciiArt.GoldenCase, slug: "scramble", piece: AsciiArt.Pieces.Scramble

  alias AsciiArt.Pieces.Scramble

  test "it says the phrases" do
    assert AsciiArt.describe(AsciiArt.new!("scramble")) ==
             "scramble: hello, world; decoding the signal; nothing is lost; see you on the other side"

    assert Scramble.describe(%{phrases: ["a.", " ", "b", "c", "d", "e"]}) ==
             "scramble: a; b; c; d; and 1 more"

    assert Scramble.describe(%{phrases: []}) == nil
  end
end
