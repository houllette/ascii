defmodule Ascii.Pieces.Rule30Test do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Rule30
  use Ascii.GoldenCase, slug: "rule-30", piece: Ascii.Pieces.Rule30
end
