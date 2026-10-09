defmodule Ascii.Pieces.DoublePendulumTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.DoublePendulum
  use Ascii.GoldenCase, slug: "double-pendulum", piece: Ascii.Pieces.DoublePendulum
end
