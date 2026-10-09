defmodule Ascii.Pieces.SundialTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Sundial
  use Ascii.GoldenCase, slug: "sundial", piece: Ascii.Pieces.Sundial
end
