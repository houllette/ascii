defmodule AsciiArt.Pieces.JuliaSetTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.JuliaSet
  use AsciiArt.GoldenCase, slug: "julia-set", piece: AsciiArt.Pieces.JuliaSet
end
