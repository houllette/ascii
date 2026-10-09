defmodule Ascii.Pieces.DnaHelixTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.DnaHelix
  use Ascii.GoldenCase, slug: "dna-helix", piece: Ascii.Pieces.DnaHelix
end
