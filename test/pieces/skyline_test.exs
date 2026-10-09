defmodule Ascii.Pieces.SkylineTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Skyline
  use Ascii.GoldenCase, slug: "skyline", piece: Ascii.Pieces.Skyline
end
