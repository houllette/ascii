defmodule AsciiArt.Pieces.SkylineTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Skyline
  use AsciiArt.GoldenCase, slug: "skyline", piece: AsciiArt.Pieces.Skyline
end
