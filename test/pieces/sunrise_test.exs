defmodule AsciiArt.Pieces.SunriseTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Sunrise
  use AsciiArt.GoldenCase, slug: "sunrise", piece: AsciiArt.Pieces.Sunrise
end
