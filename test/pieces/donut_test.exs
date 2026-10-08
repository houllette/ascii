defmodule AsciiArt.Pieces.DonutTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Donut
  use AsciiArt.GoldenCase, slug: "donut", piece: AsciiArt.Pieces.Donut
end
