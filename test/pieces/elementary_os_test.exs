defmodule AsciiArt.Pieces.ElementaryOsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.ElementaryOs
  use AsciiArt.GoldenCase, slug: "elementary-os", piece: AsciiArt.Pieces.ElementaryOs
end
