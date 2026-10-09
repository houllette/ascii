defmodule Ascii.Pieces.DonutTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Donut
  use Ascii.GoldenCase, slug: "donut", piece: Ascii.Pieces.Donut
end
