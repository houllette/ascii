defmodule Ascii.Pieces.StarlingsTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Starlings
  use Ascii.GoldenCase, slug: "starlings", piece: Ascii.Pieces.Starlings
end
