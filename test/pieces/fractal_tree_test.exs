defmodule Ascii.Pieces.FractalTreeTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.FractalTree
  use Ascii.GoldenCase, slug: "fractal-tree", piece: Ascii.Pieces.FractalTree
end
