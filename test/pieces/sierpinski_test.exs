defmodule AsciiArt.Pieces.SierpinskiTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Sierpinski
  use AsciiArt.GoldenCase, slug: "sierpinski", piece: AsciiArt.Pieces.Sierpinski
end
