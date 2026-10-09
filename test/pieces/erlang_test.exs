defmodule Ascii.Pieces.ErlangTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Erlang
  use Ascii.GoldenCase, slug: "erlang", piece: Ascii.Pieces.Erlang
end
