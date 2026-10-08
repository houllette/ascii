defmodule AsciiArt.Pieces.LinuxMintTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.LinuxMint
  use AsciiArt.GoldenCase, slug: "linux-mint", piece: AsciiArt.Pieces.LinuxMint
end
