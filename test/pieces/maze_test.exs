defmodule AsciiArt.Pieces.MazeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Maze
  use AsciiArt.GoldenCase, slug: "maze", piece: AsciiArt.Pieces.Maze
end
