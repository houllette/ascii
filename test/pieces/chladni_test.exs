defmodule AsciiArt.Pieces.ChladniTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Chladni
  use AsciiArt.GoldenCase, slug: "chladni", piece: AsciiArt.Pieces.Chladni
end
