defmodule Ascii.Pieces.CampfireTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Campfire
  use Ascii.GoldenCase, slug: "campfire", piece: Ascii.Pieces.Campfire
end
