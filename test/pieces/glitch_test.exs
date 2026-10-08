defmodule AsciiArt.Pieces.GlitchTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Glitch
  use AsciiArt.GoldenCase, slug: "glitch", piece: AsciiArt.Pieces.Glitch
end
