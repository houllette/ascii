defmodule Ascii.Pieces.SwiftTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Swift
  use Ascii.GoldenCase, slug: "swift", piece: Ascii.Pieces.Swift
end
