defmodule AsciiArt.Pieces.RockyLinuxTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.RockyLinux
  use AsciiArt.GoldenCase, slug: "rocky-linux", piece: AsciiArt.Pieces.RockyLinux
end
