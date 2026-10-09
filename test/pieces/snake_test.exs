defmodule Ascii.Pieces.SnakeTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Snake
  use Ascii.GoldenCase, slug: "snake", piece: Ascii.Pieces.Snake
end
