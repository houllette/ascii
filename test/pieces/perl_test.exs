defmodule AsciiArt.Pieces.PerlTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Perl
  use AsciiArt.GoldenCase, slug: "perl", piece: AsciiArt.Pieces.Perl
end
