defmodule Ascii.Pieces.SpiderTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Spider
  use Ascii.GoldenCase, slug: "spider", piece: Ascii.Pieces.Spider
end
