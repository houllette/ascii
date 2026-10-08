defmodule AsciiArt.Pieces.ClojureTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Clojure
  use AsciiArt.GoldenCase, slug: "clojure", piece: AsciiArt.Pieces.Clojure
end
