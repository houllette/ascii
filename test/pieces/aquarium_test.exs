defmodule AsciiArt.Pieces.AquariumTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Aquarium
  use AsciiArt.GoldenCase, slug: "aquarium", piece: AsciiArt.Pieces.Aquarium
end
