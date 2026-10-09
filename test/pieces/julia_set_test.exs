defmodule Ascii.Pieces.JuliaSetTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.JuliaSet
  use Ascii.GoldenCase, slug: "julia-set", piece: Ascii.Pieces.JuliaSet
end
