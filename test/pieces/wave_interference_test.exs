defmodule Ascii.Pieces.WaveInterferenceTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.WaveInterference
  use Ascii.GoldenCase, slug: "wave-interference", piece: Ascii.Pieces.WaveInterference
end
