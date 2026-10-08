defmodule AsciiArt.Pieces.SpringTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Spring
  use AsciiArt.GoldenCase, slug: "spring", piece: AsciiArt.Pieces.Spring
end
