defmodule AsciiArt.Pieces.WaveInterferenceTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.WaveInterference
  use AsciiArt.GoldenCase, slug: "wave-interference", piece: AsciiArt.Pieces.WaveInterference
end
