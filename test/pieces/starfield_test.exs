defmodule Ascii.Pieces.StarfieldTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Starfield
  use Ascii.GoldenCase, slug: "starfield", piece: Ascii.Pieces.Starfield
end
