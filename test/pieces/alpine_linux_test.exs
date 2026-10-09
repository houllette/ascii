defmodule Ascii.Pieces.AlpineLinuxTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.AlpineLinux
  use Ascii.GoldenCase, slug: "alpine-linux", piece: Ascii.Pieces.AlpineLinux
end
