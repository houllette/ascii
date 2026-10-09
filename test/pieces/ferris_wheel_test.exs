defmodule Ascii.Pieces.FerrisWheelTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.FerrisWheel
  use Ascii.GoldenCase, slug: "ferris-wheel", piece: Ascii.Pieces.FerrisWheel
end
