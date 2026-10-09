defmodule Ascii.Pieces.BouncingBallsTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.BouncingBalls
  use Ascii.GoldenCase, slug: "bouncing-balls", piece: Ascii.Pieces.BouncingBalls
end
