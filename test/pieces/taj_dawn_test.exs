defmodule AsciiArt.Pieces.TajDawnTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.TajDawn
  use AsciiArt.GoldenCase, slug: "taj-dawn", piece: AsciiArt.Pieces.TajDawn
end
