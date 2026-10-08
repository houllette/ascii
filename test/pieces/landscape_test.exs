defmodule AsciiArt.Pieces.LandscapeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Landscape
  use AsciiArt.GoldenCase, slug: "landscape", piece: AsciiArt.Pieces.Landscape
end
