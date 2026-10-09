defmodule AsciiArt.Pieces.DissolveTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Dissolve
  use AsciiArt.GoldenCase, slug: "dissolve", piece: AsciiArt.Pieces.Dissolve

  alias AsciiArt.Pieces.Dissolve

  test "it says the words" do
    assert AsciiArt.describe(AsciiArt.new!("dissolve")) == "dissolve: hello, hola, ciao, salut"

    assert Dissolve.describe(%{words: ~w(a b c d e f g h)}) ==
             "dissolve: a, b, c, d, e, f, and 2 more"

    assert Dissolve.describe(%{words: [" "]}) == nil
  end
end
