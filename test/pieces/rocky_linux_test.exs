defmodule Ascii.Pieces.RockyLinuxTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.RockyLinux
  use Ascii.GoldenCase, slug: "rocky-linux", piece: Ascii.Pieces.RockyLinux
end
