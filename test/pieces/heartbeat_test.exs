defmodule AsciiArt.Pieces.HeartbeatTest do
  use ExUnit.Case, async: true

  alias AsciiArt.Pieces.Heartbeat

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.Heartbeat,
    variants: [%{bpm: 30}, %{bpm: 180.4}]

  use AsciiArt.GoldenCase, slug: "heartbeat", piece: AsciiArt.Pieces.Heartbeat

  test "describe/1 tells the rate it beats at" do
    assert Heartbeat.describe(%{bpm: 72}) == "heartbeat: 72 bpm"
    assert Heartbeat.describe(%{bpm: 110.6}) == "heartbeat: 111 bpm"
    assert Heartbeat.describe(%{bpm: 10}) == "heartbeat: 30 bpm"
  end
end
