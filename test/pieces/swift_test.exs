defmodule AsciiArt.Pieces.SwiftTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Swift
  use AsciiArt.GoldenCase, slug: "swift", piece: AsciiArt.Pieces.Swift
end
