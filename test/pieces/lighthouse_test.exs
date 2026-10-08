defmodule AsciiArt.Pieces.LighthouseTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Lighthouse
  use AsciiArt.GoldenCase, slug: "lighthouse", piece: AsciiArt.Pieces.Lighthouse
end
