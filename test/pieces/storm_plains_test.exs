defmodule Ascii.Pieces.StormPlainsTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.StormPlains
  use Ascii.GoldenCase, slug: "storm-plains", piece: Ascii.Pieces.StormPlains
end
