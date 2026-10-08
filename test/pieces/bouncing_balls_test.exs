defmodule AsciiArt.Pieces.BouncingBallsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.BouncingBalls
  use AsciiArt.GoldenCase, slug: "bouncing-balls", piece: AsciiArt.Pieces.BouncingBalls
end
