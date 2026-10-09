defmodule Ascii.Pieces.NewtonsCradleTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.NewtonsCradle
  use Ascii.GoldenCase, slug: "newtons-cradle", piece: Ascii.Pieces.NewtonsCradle
end
