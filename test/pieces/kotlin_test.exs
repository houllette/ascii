defmodule Ascii.Pieces.KotlinTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Kotlin
  use Ascii.GoldenCase, slug: "kotlin", piece: Ascii.Pieces.Kotlin
end
