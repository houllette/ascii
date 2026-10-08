defmodule AsciiArt.Pieces.PlasmaTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Plasma
  use AsciiArt.GoldenCase, slug: "plasma", piece: AsciiArt.Pieces.Plasma
end
