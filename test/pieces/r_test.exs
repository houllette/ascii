defmodule AsciiArt.Pieces.RTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.R
  use AsciiArt.GoldenCase, slug: "r", piece: AsciiArt.Pieces.R
end
