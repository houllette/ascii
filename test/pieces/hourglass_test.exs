defmodule AsciiArt.Pieces.HourglassTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Hourglass
  use AsciiArt.GoldenCase, slug: "hourglass", piece: AsciiArt.Pieces.Hourglass
end
