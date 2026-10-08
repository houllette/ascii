defmodule AsciiArt.Pieces.UbuntuTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Ubuntu
  use AsciiArt.GoldenCase, slug: "ubuntu", piece: AsciiArt.Pieces.Ubuntu
end
