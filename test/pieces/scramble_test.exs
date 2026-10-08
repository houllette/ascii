defmodule AsciiArt.Pieces.ScrambleTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Scramble
  use AsciiArt.GoldenCase, slug: "scramble", piece: AsciiArt.Pieces.Scramble
end
