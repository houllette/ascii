defmodule AsciiArt.Pieces.SkeletonTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Skeleton
  use AsciiArt.GoldenCase, slug: "skeleton", piece: AsciiArt.Pieces.Skeleton
end
