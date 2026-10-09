defmodule Ascii.Pieces.RubyTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Ruby
  use Ascii.GoldenCase, slug: "ruby", piece: Ascii.Pieces.Ruby
end
