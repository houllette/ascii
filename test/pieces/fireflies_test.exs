defmodule Ascii.Pieces.FirefliesTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Fireflies
  use Ascii.GoldenCase, slug: "fireflies", piece: Ascii.Pieces.Fireflies
end
