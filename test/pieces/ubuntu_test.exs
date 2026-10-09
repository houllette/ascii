defmodule Ascii.Pieces.UbuntuTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Ubuntu
  use Ascii.GoldenCase, slug: "ubuntu", piece: Ascii.Pieces.Ubuntu
end
