defmodule AsciiArt.Pieces.LorenzTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Lorenz
  use AsciiArt.GoldenCase, slug: "lorenz", piece: AsciiArt.Pieces.Lorenz
end
