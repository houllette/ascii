defmodule AsciiArt.Pieces.DissolveTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Dissolve
  use AsciiArt.GoldenCase, slug: "dissolve", piece: AsciiArt.Pieces.Dissolve
end
