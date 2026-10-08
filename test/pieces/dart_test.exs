defmodule AsciiArt.Pieces.DartTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Dart
  use AsciiArt.GoldenCase, slug: "dart", piece: AsciiArt.Pieces.Dart
end
