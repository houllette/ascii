defmodule Ascii.Pieces.HtmlTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Html
  use Ascii.GoldenCase, slug: "html", piece: Ascii.Pieces.Html
end
