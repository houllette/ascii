defmodule Ascii.Pieces.SolarSystemTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.SolarSystem
  use Ascii.GoldenCase, slug: "solar-system", piece: Ascii.Pieces.SolarSystem
end
