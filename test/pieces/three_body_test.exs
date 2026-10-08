defmodule AsciiArt.Pieces.ThreeBodyTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.ThreeBody
  use AsciiArt.GoldenCase, slug: "three-body", piece: AsciiArt.Pieces.ThreeBody
end
