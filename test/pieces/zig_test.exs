defmodule AsciiArt.Pieces.ZigTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Zig
  use AsciiArt.GoldenCase, slug: "zig", piece: AsciiArt.Pieces.Zig
end
