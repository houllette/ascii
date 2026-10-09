defmodule Ascii.Pieces.AquariumTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Aquarium
  use Ascii.GoldenCase, slug: "aquarium", piece: Ascii.Pieces.Aquarium
end
