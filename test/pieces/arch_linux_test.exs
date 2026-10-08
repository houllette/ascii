defmodule AsciiArt.Pieces.ArchLinuxTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.ArchLinux
  use AsciiArt.GoldenCase, slug: "arch-linux", piece: AsciiArt.Pieces.ArchLinux
end
