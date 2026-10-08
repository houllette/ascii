defmodule AsciiArt.Pieces.DoomFireTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.DoomFire
  use AsciiArt.GoldenCase, slug: "doom-fire", piece: AsciiArt.Pieces.DoomFire
end
