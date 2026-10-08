defmodule AsciiArt.Pieces.CsharpTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Csharp
  use AsciiArt.GoldenCase, slug: "csharp", piece: AsciiArt.Pieces.Csharp
end
