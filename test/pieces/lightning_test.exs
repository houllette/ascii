defmodule AsciiArt.Pieces.LightningTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Lightning
  use AsciiArt.GoldenCase, slug: "lightning", piece: AsciiArt.Pieces.Lightning
end
