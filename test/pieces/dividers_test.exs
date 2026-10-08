defmodule AsciiArt.Pieces.DividersTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Dividers
  use AsciiArt.GoldenCase, slug: "dividers", piece: AsciiArt.Pieces.Dividers
end
