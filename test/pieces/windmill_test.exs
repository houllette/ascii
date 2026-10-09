defmodule Ascii.Pieces.WindmillTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Windmill
  use Ascii.GoldenCase, slug: "windmill", piece: Ascii.Pieces.Windmill
end
