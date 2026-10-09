defmodule Ascii.Pieces.FireworksTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Fireworks
  use Ascii.GoldenCase, slug: "fireworks", piece: Ascii.Pieces.Fireworks
end
