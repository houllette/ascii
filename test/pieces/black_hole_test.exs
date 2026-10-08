defmodule AsciiArt.Pieces.BlackHoleTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.BlackHole
  use AsciiArt.GoldenCase, slug: "black-hole", piece: AsciiArt.Pieces.BlackHole
end
