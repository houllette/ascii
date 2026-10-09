defmodule Ascii.Pieces.OwlTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Owl
  use Ascii.GoldenCase, slug: "owl", piece: Ascii.Pieces.Owl
end
