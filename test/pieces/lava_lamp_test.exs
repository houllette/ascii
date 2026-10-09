defmodule Ascii.Pieces.LavaLampTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.LavaLamp
  use Ascii.GoldenCase, slug: "lava-lamp", piece: Ascii.Pieces.LavaLamp
end
