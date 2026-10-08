defmodule AsciiArt.Pieces.LavaLampTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.LavaLamp
  use AsciiArt.GoldenCase, slug: "lava-lamp", piece: AsciiArt.Pieces.LavaLamp
end
