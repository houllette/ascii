defmodule AsciiArt.Pieces.CampfireTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Campfire
  use AsciiArt.GoldenCase, slug: "campfire", piece: AsciiArt.Pieces.Campfire
end
