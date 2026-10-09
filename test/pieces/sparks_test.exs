defmodule Ascii.Pieces.SparksTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Sparks
  use Ascii.GoldenCase, slug: "sparks", piece: Ascii.Pieces.Sparks
end
