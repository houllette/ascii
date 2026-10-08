defmodule AsciiArt.Pieces.PopOsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.PopOs
  use AsciiArt.GoldenCase, slug: "pop-os", piece: AsciiArt.Pieces.PopOs
end
