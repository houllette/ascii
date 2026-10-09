defmodule Ascii.Pieces.BonsaiTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Bonsai
  use Ascii.GoldenCase, slug: "bonsai", piece: Ascii.Pieces.Bonsai
end
