defmodule Ascii.Pieces.SeaSwellTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.SeaSwell
  use Ascii.GoldenCase, slug: "sea-swell", piece: Ascii.Pieces.SeaSwell
end
