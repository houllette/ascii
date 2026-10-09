defmodule Ascii.Pieces.FountainTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Fountain
  use Ascii.GoldenCase, slug: "fountain", piece: Ascii.Pieces.Fountain
end
