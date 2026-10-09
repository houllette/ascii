defmodule Ascii.Pieces.DividersTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Dividers
  use Ascii.GoldenCase, slug: "dividers", piece: Ascii.Pieces.Dividers
end
