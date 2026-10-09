defmodule Ascii.Pieces.CsharpTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Csharp
  use Ascii.GoldenCase, slug: "csharp", piece: Ascii.Pieces.Csharp
end
