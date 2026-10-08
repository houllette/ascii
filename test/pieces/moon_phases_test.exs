defmodule AsciiArt.Pieces.MoonPhasesTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.MoonPhases
  use AsciiArt.GoldenCase, slug: "moon-phases", piece: AsciiArt.Pieces.MoonPhases
end
