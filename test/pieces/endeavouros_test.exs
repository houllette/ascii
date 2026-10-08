defmodule AsciiArt.Pieces.EndeavourosTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Endeavouros
  use AsciiArt.GoldenCase, slug: "endeavouros", piece: AsciiArt.Pieces.Endeavouros
end
