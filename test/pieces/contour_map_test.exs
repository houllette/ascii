defmodule AsciiArt.Pieces.ContourMapTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.ContourMap
  use AsciiArt.GoldenCase, slug: "contour-map", piece: AsciiArt.Pieces.ContourMap
end
