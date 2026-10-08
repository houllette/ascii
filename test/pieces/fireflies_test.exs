defmodule AsciiArt.Pieces.FirefliesTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Fireflies
  use AsciiArt.GoldenCase, slug: "fireflies", piece: AsciiArt.Pieces.Fireflies
end
