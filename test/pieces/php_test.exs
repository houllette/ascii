defmodule AsciiArt.Pieces.PhpTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Php
  use AsciiArt.GoldenCase, slug: "php", piece: AsciiArt.Pieces.Php
end
