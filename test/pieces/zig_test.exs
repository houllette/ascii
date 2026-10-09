defmodule Ascii.Pieces.ZigTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Zig
  use Ascii.GoldenCase, slug: "zig", piece: Ascii.Pieces.Zig
end
