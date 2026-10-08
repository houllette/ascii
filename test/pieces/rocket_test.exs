defmodule AsciiArt.Pieces.RocketTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Rocket
  use AsciiArt.GoldenCase, slug: "rocket", piece: AsciiArt.Pieces.Rocket
end
