defmodule Ascii.Pieces.RTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.R
  use Ascii.GoldenCase, slug: "r", piece: Ascii.Pieces.R
end
