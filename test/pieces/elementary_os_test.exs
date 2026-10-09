defmodule Ascii.Pieces.ElementaryOsTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.ElementaryOs
  use Ascii.GoldenCase, slug: "elementary-os", piece: Ascii.Pieces.ElementaryOs
end
