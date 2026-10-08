defmodule AsciiArt.Pieces.BoxFramesTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.BoxFrames
  use AsciiArt.GoldenCase, slug: "box-frames", piece: AsciiArt.Pieces.BoxFrames
end
