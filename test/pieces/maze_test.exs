defmodule Ascii.Pieces.MazeTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Maze
  use Ascii.GoldenCase, slug: "maze", piece: Ascii.Pieces.Maze
end
