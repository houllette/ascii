defmodule Ascii.Pieces.PlasmaTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Plasma
  use Ascii.GoldenCase, slug: "plasma", piece: Ascii.Pieces.Plasma
end
