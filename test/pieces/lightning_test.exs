defmodule Ascii.Pieces.LightningTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Lightning
  use Ascii.GoldenCase, slug: "lightning", piece: Ascii.Pieces.Lightning
end
