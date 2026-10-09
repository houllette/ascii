defmodule Ascii.Pieces.CatTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Cat
  use Ascii.GoldenCase, slug: "cat", piece: Ascii.Pieces.Cat
end
