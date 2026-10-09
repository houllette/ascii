defmodule Ascii.Pieces.ChladniTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Chladni
  use Ascii.GoldenCase, slug: "chladni", piece: Ascii.Pieces.Chladni
end
