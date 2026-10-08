defmodule AsciiArt.Pieces.FractalTreeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.FractalTree
  use AsciiArt.GoldenCase, slug: "fractal-tree", piece: AsciiArt.Pieces.FractalTree
end
