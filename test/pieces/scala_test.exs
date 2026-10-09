defmodule Ascii.Pieces.ScalaTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Scala
  use Ascii.GoldenCase, slug: "scala", piece: Ascii.Pieces.Scala
end
