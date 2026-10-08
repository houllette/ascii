defmodule AsciiArt.Pieces.JavascriptTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Javascript
  use AsciiArt.GoldenCase, slug: "javascript", piece: AsciiArt.Pieces.Javascript
end
