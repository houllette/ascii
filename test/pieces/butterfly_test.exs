defmodule AsciiArt.Pieces.ButterflyTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Butterfly
  use AsciiArt.GoldenCase, slug: "butterfly", piece: AsciiArt.Pieces.Butterfly
end
