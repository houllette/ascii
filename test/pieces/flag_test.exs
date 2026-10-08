defmodule AsciiArt.Pieces.FlagTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Flag
  use AsciiArt.GoldenCase, slug: "flag", piece: AsciiArt.Pieces.Flag
end
