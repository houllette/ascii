defmodule Ascii.Pieces.IcosahedronTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Icosahedron
  use Ascii.GoldenCase, slug: "icosahedron", piece: Ascii.Pieces.Icosahedron
end
