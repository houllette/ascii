defmodule AsciiArt.Pieces.NotFoundTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.NotFound
  use AsciiArt.GoldenCase, slug: "not-found", piece: AsciiArt.Pieces.NotFound

  alias AsciiArt.Pieces.NotFound

  test "it says the code, the title and the message" do
    assert AsciiArt.describe(AsciiArt.new!("not-found")) ==
             "404: page not found; the page you asked for has moved or never existed"

    describe = &NotFound.describe/1
    assert describe.(%{code: "500", title: "", message: ""}) == "500"
    assert describe.(%{code: "", title: "gone", message: ""}) == "not found: gone"
    assert describe.(%{code: " ", title: "", message: " "}) == nil
  end
end
