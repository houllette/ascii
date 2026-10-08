defmodule AsciiArt.Pieces.BigTextTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.BigText
  use AsciiArt.GoldenCase, slug: "big-text", piece: AsciiArt.Pieces.BigText
end
