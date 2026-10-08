defmodule AsciiArt.Pieces.FountainTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Fountain
  use AsciiArt.GoldenCase, slug: "fountain", piece: AsciiArt.Pieces.Fountain
end
