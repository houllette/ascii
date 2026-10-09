defmodule Ascii.Pieces.OpensuseTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Opensuse
  use Ascii.GoldenCase, slug: "opensuse", piece: Ascii.Pieces.Opensuse
end
