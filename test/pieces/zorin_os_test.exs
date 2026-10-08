defmodule AsciiArt.Pieces.ZorinOsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.ZorinOs
  use AsciiArt.GoldenCase, slug: "zorin-os", piece: AsciiArt.Pieces.ZorinOs
end
