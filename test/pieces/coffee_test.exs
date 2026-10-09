defmodule Ascii.Pieces.CoffeeTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Coffee
  use Ascii.GoldenCase, slug: "coffee", piece: Ascii.Pieces.Coffee
end
