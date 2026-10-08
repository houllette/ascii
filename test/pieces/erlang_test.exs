defmodule AsciiArt.Pieces.ErlangTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Erlang
  use AsciiArt.GoldenCase, slug: "erlang", piece: AsciiArt.Pieces.Erlang
end
