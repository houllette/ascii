defmodule AsciiArt.Pieces.TypescriptTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Typescript
  use AsciiArt.GoldenCase, slug: "typescript", piece: AsciiArt.Pieces.Typescript
end
