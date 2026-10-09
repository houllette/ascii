defmodule Ascii.Pieces.SunriseTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Sunrise
  use Ascii.GoldenCase, slug: "sunrise", piece: Ascii.Pieces.Sunrise
end
