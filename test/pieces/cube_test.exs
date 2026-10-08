defmodule AsciiArt.Pieces.CubeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Cube
  use AsciiArt.GoldenCase, slug: "cube", piece: AsciiArt.Pieces.Cube
end
