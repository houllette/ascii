defmodule Ascii.Pieces.AuroraTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Aurora
  use Ascii.GoldenCase, slug: "aurora", piece: Ascii.Pieces.Aurora
end
