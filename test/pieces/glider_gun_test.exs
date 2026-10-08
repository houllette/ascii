defmodule AsciiArt.Pieces.GliderGunTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.GliderGun
  use AsciiArt.GoldenCase, slug: "glider-gun", piece: AsciiArt.Pieces.GliderGun
end
