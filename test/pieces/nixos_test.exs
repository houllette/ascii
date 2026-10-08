defmodule AsciiArt.Pieces.NixosTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Nixos
  use AsciiArt.GoldenCase, slug: "nixos", piece: AsciiArt.Pieces.Nixos
end
