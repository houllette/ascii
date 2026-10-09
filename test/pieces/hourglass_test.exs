defmodule Ascii.Pieces.HourglassTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Hourglass
  use Ascii.GoldenCase, slug: "hourglass", piece: Ascii.Pieces.Hourglass
end
