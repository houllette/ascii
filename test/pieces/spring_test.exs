defmodule Ascii.Pieces.SpringTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Spring
  use Ascii.GoldenCase, slug: "spring", piece: Ascii.Pieces.Spring
end
