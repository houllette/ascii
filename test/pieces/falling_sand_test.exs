defmodule Ascii.Pieces.FallingSandTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.FallingSand
  use Ascii.GoldenCase, slug: "falling-sand", piece: Ascii.Pieces.FallingSand
end
