defmodule AsciiArt.Pieces.CoffeeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Coffee
  use AsciiArt.GoldenCase, slug: "coffee", piece: AsciiArt.Pieces.Coffee
end
