defmodule Ascii.Pieces.SkeletonTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Skeleton
  use Ascii.GoldenCase, slug: "skeleton", piece: Ascii.Pieces.Skeleton
end
