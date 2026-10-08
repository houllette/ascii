defmodule AsciiArt.Pieces.CherryBlossomTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.CherryBlossom
  use AsciiArt.GoldenCase, slug: "cherry-blossom", piece: AsciiArt.Pieces.CherryBlossom
end
