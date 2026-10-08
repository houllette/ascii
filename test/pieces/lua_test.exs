defmodule AsciiArt.Pieces.LuaTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Lua
  use AsciiArt.GoldenCase, slug: "lua", piece: AsciiArt.Pieces.Lua
end
