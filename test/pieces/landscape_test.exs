defmodule Ascii.Pieces.LandscapeTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Landscape
  use Ascii.GoldenCase, slug: "landscape", piece: Ascii.Pieces.Landscape
end
