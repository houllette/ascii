defmodule AsciiArt.Pieces.FoxTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Fox
  use AsciiArt.GoldenCase, slug: "fox", piece: AsciiArt.Pieces.Fox
end
