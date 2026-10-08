defmodule AsciiArt.Pieces.MandelbrotTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Mandelbrot
  use AsciiArt.GoldenCase, slug: "mandelbrot", piece: AsciiArt.Pieces.Mandelbrot
end
