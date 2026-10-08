defmodule AsciiArt.Pieces.ManjaroTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Manjaro
  use AsciiArt.GoldenCase, slug: "manjaro", piece: AsciiArt.Pieces.Manjaro
end
