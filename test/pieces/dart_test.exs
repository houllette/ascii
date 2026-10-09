defmodule Ascii.Pieces.DartTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Dart
  use Ascii.GoldenCase, slug: "dart", piece: Ascii.Pieces.Dart
end
