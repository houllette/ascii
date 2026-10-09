defmodule Ascii.Pieces.CssTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Css
  use Ascii.GoldenCase, slug: "css", piece: Ascii.Pieces.Css
end
