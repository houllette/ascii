defmodule AsciiArt.Pieces.HeartbeatTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Heartbeat
  use AsciiArt.GoldenCase, slug: "heartbeat", piece: AsciiArt.Pieces.Heartbeat
end
