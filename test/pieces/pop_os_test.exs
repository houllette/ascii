defmodule Ascii.Pieces.PopOsTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.PopOs
  use Ascii.GoldenCase, slug: "pop-os", piece: Ascii.Pieces.PopOs
end
