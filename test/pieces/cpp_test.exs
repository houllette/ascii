defmodule Ascii.Pieces.CppTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Cpp
  use Ascii.GoldenCase, slug: "cpp", piece: Ascii.Pieces.Cpp
end
