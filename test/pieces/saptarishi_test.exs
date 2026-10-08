defmodule AsciiArt.Pieces.SaptarishiTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Saptarishi
  use AsciiArt.GoldenCase, slug: "saptarishi", piece: AsciiArt.Pieces.Saptarishi
end
