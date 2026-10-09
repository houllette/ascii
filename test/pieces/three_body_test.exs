defmodule Ascii.Pieces.ThreeBodyTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.ThreeBody
  use Ascii.GoldenCase, slug: "three-body", piece: Ascii.Pieces.ThreeBody
end
