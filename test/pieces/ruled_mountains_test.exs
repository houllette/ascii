defmodule AsciiArt.Pieces.RuledMountainsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.RuledMountains
  use AsciiArt.GoldenCase, slug: "ruled-mountains", piece: AsciiArt.Pieces.RuledMountains
end
