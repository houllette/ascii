defmodule Ascii.Pieces.RainTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Rain
  use Ascii.GoldenCase, slug: "rain", piece: Ascii.Pieces.Rain
end
