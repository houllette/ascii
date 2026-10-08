defmodule AsciiArt.Pieces.CppTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Cpp
  use AsciiArt.GoldenCase, slug: "cpp", piece: AsciiArt.Pieces.Cpp
end
