defmodule Ascii.Pieces.LighthouseTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Lighthouse
  use Ascii.GoldenCase, slug: "lighthouse", piece: Ascii.Pieces.Lighthouse
end
