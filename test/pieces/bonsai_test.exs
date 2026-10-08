defmodule AsciiArt.Pieces.BonsaiTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Bonsai
  use AsciiArt.GoldenCase, slug: "bonsai", piece: AsciiArt.Pieces.Bonsai
end
