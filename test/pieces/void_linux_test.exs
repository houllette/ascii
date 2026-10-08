defmodule AsciiArt.Pieces.VoidLinuxTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.VoidLinux
  use AsciiArt.GoldenCase, slug: "void-linux", piece: AsciiArt.Pieces.VoidLinux
end
