defmodule AsciiArt.Pieces.IcosahedronTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Icosahedron
  use AsciiArt.GoldenCase, slug: "icosahedron", piece: AsciiArt.Pieces.Icosahedron
end
