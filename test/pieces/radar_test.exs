defmodule AsciiArt.Pieces.RadarTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Radar
  use AsciiArt.GoldenCase, slug: "radar", piece: AsciiArt.Pieces.Radar
end
