defmodule Ascii.Pieces.ZorinOsTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.ZorinOs
  use Ascii.GoldenCase, slug: "zorin-os", piece: Ascii.Pieces.ZorinOs
end
