defmodule AsciiArt.Pieces.GalaxyTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Galaxy
  use AsciiArt.GoldenCase, slug: "galaxy", piece: AsciiArt.Pieces.Galaxy
end
