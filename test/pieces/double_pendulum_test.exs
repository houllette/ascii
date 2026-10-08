defmodule AsciiArt.Pieces.DoublePendulumTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.DoublePendulum
  use AsciiArt.GoldenCase, slug: "double-pendulum", piece: AsciiArt.Pieces.DoublePendulum
end
