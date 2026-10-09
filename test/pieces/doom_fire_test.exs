defmodule Ascii.Pieces.DoomFireTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.DoomFire
  use Ascii.GoldenCase, slug: "doom-fire", piece: Ascii.Pieces.DoomFire
end
