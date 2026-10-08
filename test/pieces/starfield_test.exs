defmodule AsciiArt.Pieces.StarfieldTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Starfield
  use AsciiArt.GoldenCase, slug: "starfield", piece: AsciiArt.Pieces.Starfield
end
