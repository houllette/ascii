defmodule Ascii.Pieces.DissolveTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Dissolve
  use Ascii.GoldenCase, slug: "dissolve", piece: Ascii.Pieces.Dissolve

  alias Ascii.Pieces.Dissolve

  test "it says the words" do
    assert Ascii.describe(Ascii.new!("dissolve")) == "dissolve: hello, hola, ciao, salut"

    assert Dissolve.describe(%{words: ~w(a b c d e f g h)}) ==
             "dissolve: a, b, c, d, e, f, and 2 more"

    assert Dissolve.describe(%{words: [" "]}) == nil
  end
end
