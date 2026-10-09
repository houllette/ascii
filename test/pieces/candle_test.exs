defmodule Ascii.Pieces.CandleTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Candle
  use Ascii.GoldenCase, slug: "candle", piece: Ascii.Pieces.Candle
end
