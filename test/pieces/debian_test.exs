defmodule AsciiArt.Pieces.DebianTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Debian
  use AsciiArt.GoldenCase, slug: "debian", piece: AsciiArt.Pieces.Debian
end
