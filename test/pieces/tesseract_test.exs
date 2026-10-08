defmodule AsciiArt.Pieces.TesseractTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Tesseract
  use AsciiArt.GoldenCase, slug: "tesseract", piece: AsciiArt.Pieces.Tesseract
end
