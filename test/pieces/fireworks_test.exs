defmodule AsciiArt.Pieces.FireworksTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Fireworks
  use AsciiArt.GoldenCase, slug: "fireworks", piece: AsciiArt.Pieces.Fireworks
end
