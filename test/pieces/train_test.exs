defmodule Ascii.Pieces.TrainTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Train
  use Ascii.GoldenCase, slug: "train", piece: Ascii.Pieces.Train
end
