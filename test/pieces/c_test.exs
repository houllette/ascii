defmodule AsciiArt.Pieces.CTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.C
  use AsciiArt.GoldenCase, slug: "c", piece: AsciiArt.Pieces.C
end
