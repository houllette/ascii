defmodule AsciiArt.Pieces.SnowfallTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Snowfall
  use AsciiArt.GoldenCase, slug: "snowfall", piece: AsciiArt.Pieces.Snowfall
end
