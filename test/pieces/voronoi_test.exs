defmodule Ascii.Pieces.VoronoiTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Voronoi
  use Ascii.GoldenCase, slug: "voronoi", piece: Ascii.Pieces.Voronoi
end
