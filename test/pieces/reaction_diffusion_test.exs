defmodule AsciiArt.Pieces.ReactionDiffusionTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.ReactionDiffusion
  use AsciiArt.GoldenCase, slug: "reaction-diffusion", piece: AsciiArt.Pieces.ReactionDiffusion
end
