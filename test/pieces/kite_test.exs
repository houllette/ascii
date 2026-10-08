defmodule AsciiArt.Pieces.KiteTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Kite
  use AsciiArt.GoldenCase, slug: "kite", piece: AsciiArt.Pieces.Kite
end
