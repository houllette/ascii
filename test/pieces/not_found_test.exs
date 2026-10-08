defmodule AsciiArt.Pieces.NotFoundTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.NotFound
  use AsciiArt.GoldenCase, slug: "not-found", piece: AsciiArt.Pieces.NotFound
end
