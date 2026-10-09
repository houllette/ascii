defmodule Ascii.Pieces.TunnelTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Tunnel
  use Ascii.GoldenCase, slug: "tunnel", piece: Ascii.Pieces.Tunnel
end
