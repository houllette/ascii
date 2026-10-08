defmodule AsciiArt.Pieces.SnakeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Snake
  use AsciiArt.GoldenCase, slug: "snake", piece: AsciiArt.Pieces.Snake
end
