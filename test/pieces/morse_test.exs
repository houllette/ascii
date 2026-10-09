defmodule AsciiArt.Pieces.MorseTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Morse
  use AsciiArt.GoldenCase, slug: "morse", piece: AsciiArt.Pieces.Morse

  alias AsciiArt.Pieces.Morse

  test "it says the message" do
    assert AsciiArt.describe(AsciiArt.new!("morse")) == "morse: hello world"
    assert Morse.describe(%{text: " sos "}) == "morse: sos"
    assert Morse.describe(%{text: ""}) == nil
  end
end
