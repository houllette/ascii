defmodule Ascii.Pieces.ScrambleTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Scramble
  use Ascii.GoldenCase, slug: "scramble", piece: Ascii.Pieces.Scramble

  alias Ascii.Pieces.Scramble

  test "it says the phrases" do
    assert Ascii.describe(Ascii.new!("scramble")) ==
             "scramble: hello, world; decoding the signal; nothing is lost; see you on the other side"

    assert Scramble.describe(%{phrases: ["a.", " ", "b", "c", "d", "e"]}) ==
             "scramble: a; b; c; d; and 1 more"

    assert Scramble.describe(%{phrases: []}) == nil
  end
end
