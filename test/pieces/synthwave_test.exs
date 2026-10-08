defmodule AsciiArt.Pieces.SynthwaveTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Synthwave
  use AsciiArt.GoldenCase, slug: "synthwave", piece: AsciiArt.Pieces.Synthwave
end
