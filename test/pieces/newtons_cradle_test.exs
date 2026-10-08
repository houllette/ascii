defmodule AsciiArt.Pieces.NewtonsCradleTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.NewtonsCradle
  use AsciiArt.GoldenCase, slug: "newtons-cradle", piece: AsciiArt.Pieces.NewtonsCradle
end
