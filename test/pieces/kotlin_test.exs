defmodule AsciiArt.Pieces.KotlinTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Kotlin
  use AsciiArt.GoldenCase, slug: "kotlin", piece: AsciiArt.Pieces.Kotlin
end
