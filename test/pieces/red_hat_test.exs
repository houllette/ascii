defmodule Ascii.Pieces.RedHatTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.RedHat
  use Ascii.GoldenCase, slug: "red-hat", piece: Ascii.Pieces.RedHat
end
