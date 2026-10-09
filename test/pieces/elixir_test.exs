defmodule Ascii.Pieces.ElixirTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Elixir
  use Ascii.GoldenCase, slug: "elixir", piece: Ascii.Pieces.Elixir
end
