defmodule AsciiArt.Pieces.CssTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Css
  use AsciiArt.GoldenCase, slug: "css", piece: AsciiArt.Pieces.Css
end
