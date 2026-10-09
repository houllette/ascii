defmodule Ascii.Pieces.KiteTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Kite
  use Ascii.GoldenCase, slug: "kite", piece: Ascii.Pieces.Kite
end
