defmodule AsciiArt.Pieces.SeaSwellTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.SeaSwell
  use AsciiArt.GoldenCase, slug: "sea-swell", piece: AsciiArt.Pieces.SeaSwell
end
