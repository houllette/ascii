defmodule AsciiArt.Pieces.AlpineLinuxTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.AlpineLinux
  use AsciiArt.GoldenCase, slug: "alpine-linux", piece: AsciiArt.Pieces.AlpineLinux
end
