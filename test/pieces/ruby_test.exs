defmodule AsciiArt.Pieces.RubyTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Ruby
  use AsciiArt.GoldenCase, slug: "ruby", piece: AsciiArt.Pieces.Ruby
end
