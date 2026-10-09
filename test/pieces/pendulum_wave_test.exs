defmodule Ascii.Pieces.PendulumWaveTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.PendulumWave
  use Ascii.GoldenCase, slug: "pendulum-wave", piece: Ascii.Pieces.PendulumWave
end
