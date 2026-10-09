defmodule Ascii.Pieces.VinylTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Vinyl
  use Ascii.GoldenCase, slug: "vinyl", piece: Ascii.Pieces.Vinyl
end
