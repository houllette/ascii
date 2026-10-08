defmodule AsciiArt.Pieces.SpiderTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Spider
  use AsciiArt.GoldenCase, slug: "spider", piece: AsciiArt.Pieces.Spider
end
