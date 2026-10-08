defmodule AsciiArt.Pieces.AnalogClockTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.AnalogClock
  use AsciiArt.GoldenCase, slug: "analog-clock", piece: AsciiArt.Pieces.AnalogClock
end
