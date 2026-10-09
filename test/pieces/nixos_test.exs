defmodule Ascii.Pieces.NixosTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Nixos
  use Ascii.GoldenCase, slug: "nixos", piece: Ascii.Pieces.Nixos
end
