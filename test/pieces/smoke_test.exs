defmodule Ascii.Pieces.SmokeTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Smoke
  use Ascii.GoldenCase, slug: "smoke", piece: Ascii.Pieces.Smoke
end
