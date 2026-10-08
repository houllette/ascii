defmodule AsciiArt.Pieces.AlmalinuxTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Almalinux
  use AsciiArt.GoldenCase, slug: "almalinux", piece: AsciiArt.Pieces.Almalinux
end
