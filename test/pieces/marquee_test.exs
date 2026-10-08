defmodule AsciiArt.Pieces.MarqueeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Marquee
  use AsciiArt.GoldenCase, slug: "marquee", piece: AsciiArt.Pieces.Marquee
end
