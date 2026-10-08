defmodule AsciiArt.Pieces.TerminalTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Terminal
  use AsciiArt.GoldenCase, slug: "terminal", piece: AsciiArt.Pieces.Terminal
end
