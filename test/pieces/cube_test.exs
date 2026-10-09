defmodule Ascii.Pieces.CubeTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Cube
  use Ascii.GoldenCase, slug: "cube", piece: Ascii.Pieces.Cube
end
