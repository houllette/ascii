defmodule Ascii.Pieces.LuaTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Lua
  use Ascii.GoldenCase, slug: "lua", piece: Ascii.Pieces.Lua
end
