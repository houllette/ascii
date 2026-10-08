defmodule AsciiArt.Pieces.CandleTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Candle
  use AsciiArt.GoldenCase, slug: "candle", piece: AsciiArt.Pieces.Candle
end
