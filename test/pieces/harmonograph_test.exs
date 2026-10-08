defmodule AsciiArt.Pieces.HarmonographTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Harmonograph
  use AsciiArt.GoldenCase, slug: "harmonograph", piece: AsciiArt.Pieces.Harmonograph
end
