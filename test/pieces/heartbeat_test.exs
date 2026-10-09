defmodule Ascii.Pieces.HeartbeatTest do
  use ExUnit.Case, async: true

  alias Ascii.Pieces.Heartbeat

  use Ascii.ContractCase,
    piece: Ascii.Pieces.Heartbeat,
    variants: [%{bpm: 30}, %{bpm: 180.4}]

  use Ascii.GoldenCase, slug: "heartbeat", piece: Ascii.Pieces.Heartbeat

  test "describe/1 tells the rate it beats at" do
    assert Heartbeat.describe(%{bpm: 72}) == "heartbeat: 72 bpm"
    assert Heartbeat.describe(%{bpm: 110.6}) == "heartbeat: 111 bpm"
    assert Heartbeat.describe(%{bpm: 10}) == "heartbeat: 30 bpm"
  end
end
