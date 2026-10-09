defmodule Ascii.Pieces.GalaxyTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Galaxy
  use Ascii.GoldenCase, slug: "galaxy", piece: Ascii.Pieces.Galaxy
end
