defmodule AsciiArt.Pieces.SolarSystemTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.SolarSystem
  use AsciiArt.GoldenCase, slug: "solar-system", piece: AsciiArt.Pieces.SolarSystem
end
