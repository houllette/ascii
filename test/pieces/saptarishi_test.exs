defmodule Ascii.Pieces.SaptarishiTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Saptarishi
  use Ascii.GoldenCase, slug: "saptarishi", piece: Ascii.Pieces.Saptarishi
end
