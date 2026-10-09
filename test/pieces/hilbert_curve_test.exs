defmodule Ascii.Pieces.HilbertCurveTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.HilbertCurve
  use Ascii.GoldenCase, slug: "hilbert-curve", piece: Ascii.Pieces.HilbertCurve
end
