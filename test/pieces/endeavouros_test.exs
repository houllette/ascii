defmodule Ascii.Pieces.EndeavourosTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Endeavouros
  use Ascii.GoldenCase, slug: "endeavouros", piece: Ascii.Pieces.Endeavouros
end
