defmodule AsciiArt.Pieces.Rule30Test do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Rule30
  use AsciiArt.GoldenCase, slug: "rule-30", piece: AsciiArt.Pieces.Rule30
end
