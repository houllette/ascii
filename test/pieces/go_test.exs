defmodule Ascii.Pieces.GoTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Go
  use Ascii.GoldenCase, slug: "go", piece: Ascii.Pieces.Go
end
