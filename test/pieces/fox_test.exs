defmodule Ascii.Pieces.FoxTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Fox
  use Ascii.GoldenCase, slug: "fox", piece: Ascii.Pieces.Fox
end
