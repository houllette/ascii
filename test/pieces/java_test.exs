defmodule Ascii.Pieces.JavaTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Java
  use Ascii.GoldenCase, slug: "java", piece: Ascii.Pieces.Java
end
