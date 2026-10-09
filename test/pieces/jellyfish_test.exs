defmodule Ascii.Pieces.JellyfishTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Jellyfish
  use Ascii.GoldenCase, slug: "jellyfish", piece: Ascii.Pieces.Jellyfish
end
