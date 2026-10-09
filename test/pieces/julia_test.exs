defmodule Ascii.Pieces.JuliaTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Julia
  use Ascii.GoldenCase, slug: "julia", piece: Ascii.Pieces.Julia
end
