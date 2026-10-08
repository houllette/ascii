defmodule AsciiArt.Pieces.ElixirTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Elixir
  use AsciiArt.GoldenCase, slug: "elixir", piece: AsciiArt.Pieces.Elixir
end
