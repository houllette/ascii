defmodule AsciiArt.Pieces.StarlingsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Starlings
  use AsciiArt.GoldenCase, slug: "starlings", piece: AsciiArt.Pieces.Starlings
end
