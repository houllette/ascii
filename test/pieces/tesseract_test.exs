defmodule Ascii.Pieces.TesseractTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Tesseract
  use Ascii.GoldenCase, slug: "tesseract", piece: Ascii.Pieces.Tesseract
end
