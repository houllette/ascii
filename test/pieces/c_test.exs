defmodule Ascii.Pieces.CTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.C
  use Ascii.GoldenCase, slug: "c", piece: Ascii.Pieces.C
end
