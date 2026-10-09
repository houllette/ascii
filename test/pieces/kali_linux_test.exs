defmodule Ascii.Pieces.KaliLinuxTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.KaliLinux
  use Ascii.GoldenCase, slug: "kali-linux", piece: Ascii.Pieces.KaliLinux
end
