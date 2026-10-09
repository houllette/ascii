defmodule Ascii.Pieces.MorseTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Morse
  use Ascii.GoldenCase, slug: "morse", piece: Ascii.Pieces.Morse

  alias Ascii.Pieces.Morse

  test "it says the message" do
    assert Ascii.describe(Ascii.new!("morse")) == "morse: hello world"
    assert Morse.describe(%{text: " sos "}) == "morse: sos"
    assert Morse.describe(%{text: ""}) == nil
  end
end
