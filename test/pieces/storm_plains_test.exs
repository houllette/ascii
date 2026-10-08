defmodule AsciiArt.Pieces.StormPlainsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.StormPlains
  use AsciiArt.GoldenCase, slug: "storm-plains", piece: AsciiArt.Pieces.StormPlains
end
