defmodule AsciiArt.Pieces.VoronoiTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Voronoi
  use AsciiArt.GoldenCase, slug: "voronoi", piece: AsciiArt.Pieces.Voronoi
end
