defmodule AsciiArt.Pieces.EclipseTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Eclipse
  use AsciiArt.GoldenCase, slug: "eclipse", piece: AsciiArt.Pieces.Eclipse
end
