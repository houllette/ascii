defmodule AsciiArt.Pieces.FileTreeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.FileTree
  use AsciiArt.GoldenCase, slug: "file-tree", piece: AsciiArt.Pieces.FileTree
end
