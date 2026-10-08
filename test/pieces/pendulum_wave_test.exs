defmodule AsciiArt.Pieces.PendulumWaveTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.PendulumWave
  use AsciiArt.GoldenCase, slug: "pendulum-wave", piece: AsciiArt.Pieces.PendulumWave
end
