defmodule Ascii.Pieces.ContourMapTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.ContourMap
  use Ascii.GoldenCase, slug: "contour-map", piece: Ascii.Pieces.ContourMap
end
