defmodule Ascii.Pieces.TuxTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Tux
  use Ascii.GoldenCase, slug: "tux", piece: Ascii.Pieces.Tux
end
