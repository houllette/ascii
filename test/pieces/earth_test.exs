defmodule AsciiArt.Pieces.EarthTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Earth
  use AsciiArt.GoldenCase, slug: "earth", piece: AsciiArt.Pieces.Earth
end
