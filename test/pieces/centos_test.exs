defmodule AsciiArt.Pieces.CentosTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Centos
  use AsciiArt.GoldenCase, slug: "centos", piece: AsciiArt.Pieces.Centos
end
