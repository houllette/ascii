defmodule Ascii.Pieces.BoxFramesTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.BoxFrames
  use Ascii.GoldenCase, slug: "box-frames", piece: Ascii.Pieces.BoxFrames
end
