defmodule AsciiArt.Pieces.OcamlTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Ocaml
  use AsciiArt.GoldenCase, slug: "ocaml", piece: AsciiArt.Pieces.Ocaml
end
