defmodule Ascii.Pieces.VoidLinuxTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.VoidLinux
  use Ascii.GoldenCase, slug: "void-linux", piece: Ascii.Pieces.VoidLinux
end
