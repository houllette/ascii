defmodule Ascii.Pieces.RotozoomerTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Rotozoomer
  use Ascii.GoldenCase, slug: "rotozoomer", piece: Ascii.Pieces.Rotozoomer
end
