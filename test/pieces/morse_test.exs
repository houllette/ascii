defmodule AsciiArt.Pieces.MorseTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Morse
  use AsciiArt.GoldenCase, slug: "morse", piece: AsciiArt.Pieces.Morse
end
