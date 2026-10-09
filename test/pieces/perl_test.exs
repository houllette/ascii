defmodule Ascii.Pieces.PerlTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Perl
  use Ascii.GoldenCase, slug: "perl", piece: Ascii.Pieces.Perl
end
