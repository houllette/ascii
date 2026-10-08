defmodule AsciiArt.Pieces.HilbertCurveTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.HilbertCurve
  use AsciiArt.GoldenCase, slug: "hilbert-curve", piece: AsciiArt.Pieces.HilbertCurve
end
