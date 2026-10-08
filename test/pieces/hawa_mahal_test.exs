defmodule AsciiArt.Pieces.HawaMahalTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.HawaMahal
  use AsciiArt.GoldenCase, slug: "hawa-mahal", piece: AsciiArt.Pieces.HawaMahal
end
