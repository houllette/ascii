defmodule AsciiArt.Pieces.SparksTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Sparks
  use AsciiArt.GoldenCase, slug: "sparks", piece: AsciiArt.Pieces.Sparks
end
