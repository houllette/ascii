defmodule AsciiArt.Pieces.TvStaticTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.TvStatic
  use AsciiArt.GoldenCase, slug: "tv-static", piece: AsciiArt.Pieces.TvStatic
end
