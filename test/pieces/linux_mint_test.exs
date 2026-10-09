defmodule Ascii.Pieces.LinuxMintTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.LinuxMint
  use Ascii.GoldenCase, slug: "linux-mint", piece: Ascii.Pieces.LinuxMint
end
