defmodule Ascii.Pieces.GliderGunTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.GliderGun
  use Ascii.GoldenCase, slug: "glider-gun", piece: Ascii.Pieces.GliderGun
end
