defmodule Ascii.Pieces.HarmonographTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Harmonograph
  use Ascii.GoldenCase, slug: "harmonograph", piece: Ascii.Pieces.Harmonograph
end
