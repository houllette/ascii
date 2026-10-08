defmodule AsciiArt.Pieces.OpensuseTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Opensuse
  use AsciiArt.GoldenCase, slug: "opensuse", piece: AsciiArt.Pieces.Opensuse
end
