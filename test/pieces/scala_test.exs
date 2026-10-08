defmodule AsciiArt.Pieces.ScalaTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Scala
  use AsciiArt.GoldenCase, slug: "scala", piece: AsciiArt.Pieces.Scala
end
