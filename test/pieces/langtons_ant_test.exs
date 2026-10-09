defmodule Ascii.Pieces.LangtonsAntTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.LangtonsAnt
  use Ascii.GoldenCase, slug: "langtons-ant", piece: Ascii.Pieces.LangtonsAnt
end
