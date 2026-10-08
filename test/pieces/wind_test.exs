defmodule AsciiArt.Pieces.WindTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Wind
  use AsciiArt.GoldenCase, slug: "wind", piece: AsciiArt.Pieces.Wind
end
