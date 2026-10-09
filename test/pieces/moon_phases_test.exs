defmodule Ascii.Pieces.MoonPhasesTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.MoonPhases
  use Ascii.GoldenCase, slug: "moon-phases", piece: Ascii.Pieces.MoonPhases
end
