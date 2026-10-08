defmodule AsciiArt.Pieces.FallingSandTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.FallingSand
  use AsciiArt.GoldenCase, slug: "falling-sand", piece: AsciiArt.Pieces.FallingSand
end
