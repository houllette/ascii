defmodule AsciiArt.Pieces.RainTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Rain
  use AsciiArt.GoldenCase, slug: "rain", piece: AsciiArt.Pieces.Rain
end
