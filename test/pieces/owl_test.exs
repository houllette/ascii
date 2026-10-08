defmodule AsciiArt.Pieces.OwlTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Owl
  use AsciiArt.GoldenCase, slug: "owl", piece: AsciiArt.Pieces.Owl
end
