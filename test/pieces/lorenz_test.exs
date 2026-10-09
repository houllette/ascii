defmodule Ascii.Pieces.LorenzTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Lorenz
  use Ascii.GoldenCase, slug: "lorenz", piece: Ascii.Pieces.Lorenz
end
