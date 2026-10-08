defmodule AsciiArt.Pieces.MatrixRainTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.MatrixRain
  use AsciiArt.GoldenCase, slug: "matrix-rain", piece: AsciiArt.Pieces.MatrixRain
end
