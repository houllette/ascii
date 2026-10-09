defmodule Ascii.Pieces.HaskellTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Haskell
  use Ascii.GoldenCase, slug: "haskell", piece: Ascii.Pieces.Haskell
end
