defmodule Ascii.Pieces.TvStaticTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.TvStatic
  use Ascii.GoldenCase, slug: "tv-static", piece: Ascii.Pieces.TvStatic
end
