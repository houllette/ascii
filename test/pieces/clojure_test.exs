defmodule Ascii.Pieces.ClojureTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Clojure
  use Ascii.GoldenCase, slug: "clojure", piece: Ascii.Pieces.Clojure
end
