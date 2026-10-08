defmodule AsciiArt.Pieces.LangtonsAntTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.LangtonsAnt
  use AsciiArt.GoldenCase, slug: "langtons-ant", piece: AsciiArt.Pieces.LangtonsAnt
end
