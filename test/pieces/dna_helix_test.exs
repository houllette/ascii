defmodule AsciiArt.Pieces.DnaHelixTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.DnaHelix
  use AsciiArt.GoldenCase, slug: "dna-helix", piece: AsciiArt.Pieces.DnaHelix
end
