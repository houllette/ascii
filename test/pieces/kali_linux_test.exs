defmodule AsciiArt.Pieces.KaliLinuxTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.KaliLinux
  use AsciiArt.GoldenCase, slug: "kali-linux", piece: AsciiArt.Pieces.KaliLinux
end
