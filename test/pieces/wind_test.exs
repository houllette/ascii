defmodule Ascii.Pieces.WindTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Wind
  use Ascii.GoldenCase, slug: "wind", piece: Ascii.Pieces.Wind
end
