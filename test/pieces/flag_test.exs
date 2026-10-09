defmodule Ascii.Pieces.FlagTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Flag
  use Ascii.GoldenCase, slug: "flag", piece: Ascii.Pieces.Flag
end
