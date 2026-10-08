defmodule AsciiArt.Pieces.SplitFlapTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.SplitFlap
  use AsciiArt.GoldenCase, slug: "split-flap", piece: AsciiArt.Pieces.SplitFlap
end
