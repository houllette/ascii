defmodule AsciiArt.Pieces.PondRipplesTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.PondRipples
  use AsciiArt.GoldenCase, slug: "pond-ripples", piece: AsciiArt.Pieces.PondRipples
end
