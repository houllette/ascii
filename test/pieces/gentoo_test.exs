defmodule Ascii.Pieces.GentooTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Gentoo
  use Ascii.GoldenCase, slug: "gentoo", piece: Ascii.Pieces.Gentoo
end
