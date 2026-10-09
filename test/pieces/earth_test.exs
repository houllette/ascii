defmodule Ascii.Pieces.EarthTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Earth
  use Ascii.GoldenCase, slug: "earth", piece: Ascii.Pieces.Earth
end
