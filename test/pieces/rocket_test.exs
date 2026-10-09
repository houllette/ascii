defmodule Ascii.Pieces.RocketTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Rocket
  use Ascii.GoldenCase, slug: "rocket", piece: Ascii.Pieces.Rocket
end
