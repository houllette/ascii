defmodule AsciiArt.Pieces.WaveTextTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.WaveText
  use AsciiArt.GoldenCase, slug: "wave-text", piece: AsciiArt.Pieces.WaveText
end
