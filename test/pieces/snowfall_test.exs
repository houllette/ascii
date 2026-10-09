defmodule Ascii.Pieces.SnowfallTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Snowfall
  use Ascii.GoldenCase, slug: "snowfall", piece: Ascii.Pieces.Snowfall
end
