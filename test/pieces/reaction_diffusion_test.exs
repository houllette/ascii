defmodule Ascii.Pieces.ReactionDiffusionTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.ReactionDiffusion
  use Ascii.GoldenCase, slug: "reaction-diffusion", piece: Ascii.Pieces.ReactionDiffusion
end
