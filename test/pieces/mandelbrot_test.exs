defmodule Ascii.Pieces.MandelbrotTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Mandelbrot
  use Ascii.GoldenCase, slug: "mandelbrot", piece: Ascii.Pieces.Mandelbrot
end
