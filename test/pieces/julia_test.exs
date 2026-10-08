defmodule AsciiArt.Pieces.JuliaTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Julia
  use AsciiArt.GoldenCase, slug: "julia", piece: AsciiArt.Pieces.Julia
end
