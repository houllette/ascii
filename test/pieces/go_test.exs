defmodule AsciiArt.Pieces.GoTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Go
  use AsciiArt.GoldenCase, slug: "go", piece: AsciiArt.Pieces.Go
end
