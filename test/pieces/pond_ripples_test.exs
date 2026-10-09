defmodule Ascii.Pieces.PondRipplesTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.PondRipples
  use Ascii.GoldenCase, slug: "pond-ripples", piece: Ascii.Pieces.PondRipples
end
