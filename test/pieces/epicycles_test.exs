defmodule AsciiArt.Pieces.EpicyclesTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Epicycles
  use AsciiArt.GoldenCase, slug: "epicycles", piece: AsciiArt.Pieces.Epicycles
end
