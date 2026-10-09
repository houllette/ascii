defmodule Ascii.Pieces.HawaMahalTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.HawaMahal
  use Ascii.GoldenCase, slug: "hawa-mahal", piece: Ascii.Pieces.HawaMahal
end
