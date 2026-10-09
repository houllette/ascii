defmodule Ascii.Pieces.SynthwaveTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Synthwave
  use Ascii.GoldenCase, slug: "synthwave", piece: Ascii.Pieces.Synthwave
end
