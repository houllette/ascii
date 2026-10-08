defmodule AsciiArt.Pieces.WindmillTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Windmill
  use AsciiArt.GoldenCase, slug: "windmill", piece: AsciiArt.Pieces.Windmill
end
