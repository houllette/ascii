defmodule Ascii.Pieces.TypescriptTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Typescript
  use Ascii.GoldenCase, slug: "typescript", piece: Ascii.Pieces.Typescript
end
