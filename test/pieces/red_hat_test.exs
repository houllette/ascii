defmodule AsciiArt.Pieces.RedHatTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.RedHat
  use AsciiArt.GoldenCase, slug: "red-hat", piece: AsciiArt.Pieces.RedHat
end
