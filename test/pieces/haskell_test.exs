defmodule AsciiArt.Pieces.HaskellTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Haskell
  use AsciiArt.GoldenCase, slug: "haskell", piece: AsciiArt.Pieces.Haskell
end
