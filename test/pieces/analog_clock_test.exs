defmodule Ascii.Pieces.AnalogClockTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.AnalogClock
  use Ascii.GoldenCase, slug: "analog-clock", piece: Ascii.Pieces.AnalogClock
end
