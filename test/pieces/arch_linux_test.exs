defmodule Ascii.Pieces.ArchLinuxTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.ArchLinux
  use Ascii.GoldenCase, slug: "arch-linux", piece: Ascii.Pieces.ArchLinux
end
