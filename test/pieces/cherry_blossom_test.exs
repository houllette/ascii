defmodule Ascii.Pieces.CherryBlossomTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.CherryBlossom
  use Ascii.GoldenCase, slug: "cherry-blossom", piece: Ascii.Pieces.CherryBlossom
end
