defmodule Ascii.Pieces.AlmalinuxTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Almalinux
  use Ascii.GoldenCase, slug: "almalinux", piece: Ascii.Pieces.Almalinux
end
