defmodule AsciiArt.Pieces.PluckedStringTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.PluckedString
  use AsciiArt.GoldenCase, slug: "plucked-string", piece: AsciiArt.Pieces.PluckedString
end
