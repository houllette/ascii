defmodule AsciiArt.Pieces.TuxTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Tux
  use AsciiArt.GoldenCase, slug: "tux", piece: AsciiArt.Pieces.Tux
end
