defmodule AsciiArt.Pieces.DigitalClockTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.DigitalClock
  use AsciiArt.GoldenCase, slug: "digital-clock", piece: AsciiArt.Pieces.DigitalClock
end
