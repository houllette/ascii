defmodule AsciiArt.Pieces.JavaTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Java
  use AsciiArt.GoldenCase, slug: "java", piece: AsciiArt.Pieces.Java
end
