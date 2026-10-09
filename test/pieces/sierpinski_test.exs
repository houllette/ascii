defmodule Ascii.Pieces.SierpinskiTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Sierpinski
  use Ascii.GoldenCase, slug: "sierpinski", piece: Ascii.Pieces.Sierpinski
end
