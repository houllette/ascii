defmodule AsciiArt.Pieces.TypewriterTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Typewriter
  use AsciiArt.GoldenCase, slug: "typewriter", piece: AsciiArt.Pieces.Typewriter
end
