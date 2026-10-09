defmodule Ascii.Pieces.OcamlTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Ocaml
  use Ascii.GoldenCase, slug: "ocaml", piece: Ascii.Pieces.Ocaml
end
