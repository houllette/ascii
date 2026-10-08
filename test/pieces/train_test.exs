defmodule AsciiArt.Pieces.TrainTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Train
  use AsciiArt.GoldenCase, slug: "train", piece: AsciiArt.Pieces.Train
end
