defmodule AsciiArt.Pieces.CatTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Cat
  use AsciiArt.GoldenCase, slug: "cat", piece: AsciiArt.Pieces.Cat
end
