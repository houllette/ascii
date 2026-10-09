defmodule Ascii.Pieces.MatrixRainTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.MatrixRain
  use Ascii.GoldenCase, slug: "matrix-rain", piece: Ascii.Pieces.MatrixRain
end
