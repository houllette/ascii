defmodule AsciiArt.Pieces.HtmlTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Html
  use AsciiArt.GoldenCase, slug: "html", piece: AsciiArt.Pieces.Html
end
