defmodule AsciiArt.Pieces.VinylTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Vinyl
  use AsciiArt.GoldenCase, slug: "vinyl", piece: AsciiArt.Pieces.Vinyl
end
