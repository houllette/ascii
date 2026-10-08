defmodule AsciiArt.Pieces.JellyfishTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Jellyfish
  use AsciiArt.GoldenCase, slug: "jellyfish", piece: AsciiArt.Pieces.Jellyfish
end
