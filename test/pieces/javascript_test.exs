defmodule Ascii.Pieces.JavascriptTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Javascript
  use Ascii.GoldenCase, slug: "javascript", piece: Ascii.Pieces.Javascript
end
