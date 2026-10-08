defmodule AsciiArt.Pieces.RotozoomerTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Rotozoomer
  use AsciiArt.GoldenCase, slug: "rotozoomer", piece: AsciiArt.Pieces.Rotozoomer
end
