defmodule AsciiArt.Pieces.TunnelTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Tunnel
  use AsciiArt.GoldenCase, slug: "tunnel", piece: AsciiArt.Pieces.Tunnel
end
