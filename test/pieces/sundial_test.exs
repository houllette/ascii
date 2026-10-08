defmodule AsciiArt.Pieces.SundialTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Sundial
  use AsciiArt.GoldenCase, slug: "sundial", piece: AsciiArt.Pieces.Sundial
end
