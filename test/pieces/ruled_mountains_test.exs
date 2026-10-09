defmodule Ascii.Pieces.RuledMountainsTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.RuledMountains
  use Ascii.GoldenCase, slug: "ruled-mountains", piece: Ascii.Pieces.RuledMountains
end
