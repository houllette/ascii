defmodule Ascii.Pieces.WhaleTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Whale
  use Ascii.GoldenCase, slug: "whale", piece: Ascii.Pieces.Whale
end
