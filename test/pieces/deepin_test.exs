defmodule AsciiArt.Pieces.DeepinTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Deepin
  use AsciiArt.GoldenCase, slug: "deepin", piece: AsciiArt.Pieces.Deepin
end
