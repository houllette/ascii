defmodule AsciiArt.Pieces.PlanetTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Planet
  use AsciiArt.GoldenCase, slug: "planet", piece: AsciiArt.Pieces.Planet
end
