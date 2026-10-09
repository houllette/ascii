defmodule Ascii.Pieces.EpicyclesTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Epicycles
  use Ascii.GoldenCase, slug: "epicycles", piece: Ascii.Pieces.Epicycles
end
