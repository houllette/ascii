defmodule Ascii.Pieces.PhpTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Php
  use Ascii.GoldenCase, slug: "php", piece: Ascii.Pieces.Php
end
