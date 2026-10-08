defmodule AsciiArt.Pieces.AuroraTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Aurora
  use AsciiArt.GoldenCase, slug: "aurora", piece: AsciiArt.Pieces.Aurora
end
