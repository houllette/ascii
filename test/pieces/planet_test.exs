defmodule Ascii.Pieces.PlanetTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Planet
  use Ascii.GoldenCase, slug: "planet", piece: Ascii.Pieces.Planet
end
