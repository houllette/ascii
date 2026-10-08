defmodule AsciiArt.Pieces.WhaleTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Whale
  use AsciiArt.GoldenCase, slug: "whale", piece: AsciiArt.Pieces.Whale
end
