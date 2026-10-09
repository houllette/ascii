defmodule Ascii.Pieces.DebianTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Debian
  use Ascii.GoldenCase, slug: "debian", piece: Ascii.Pieces.Debian
end
