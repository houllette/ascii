defmodule AsciiArt.Pieces.FerrisWheelTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.FerrisWheel
  use AsciiArt.GoldenCase, slug: "ferris-wheel", piece: AsciiArt.Pieces.FerrisWheel
end
