defmodule Ascii.Pieces.PluckedStringTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.PluckedString
  use Ascii.GoldenCase, slug: "plucked-string", piece: Ascii.Pieces.PluckedString
end
