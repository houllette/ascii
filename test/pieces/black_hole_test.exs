defmodule Ascii.Pieces.BlackHoleTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.BlackHole
  use Ascii.GoldenCase, slug: "black-hole", piece: Ascii.Pieces.BlackHole
end
