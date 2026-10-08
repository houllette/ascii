defmodule AsciiArt.Pieces.SmokeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Smoke
  use AsciiArt.GoldenCase, slug: "smoke", piece: AsciiArt.Pieces.Smoke
end
