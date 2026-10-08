defmodule AsciiArt.Pieces.GentooTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Gentoo
  use AsciiArt.GoldenCase, slug: "gentoo", piece: AsciiArt.Pieces.Gentoo
end
