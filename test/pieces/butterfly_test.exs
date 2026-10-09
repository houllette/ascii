defmodule Ascii.Pieces.ButterflyTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Butterfly
  use Ascii.GoldenCase, slug: "butterfly", piece: Ascii.Pieces.Butterfly
end
