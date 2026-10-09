defmodule Ascii.Pieces.ManjaroTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Manjaro
  use Ascii.GoldenCase, slug: "manjaro", piece: Ascii.Pieces.Manjaro
end
