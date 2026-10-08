defmodule AsciiArt.Pieces.PythonTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Python
  use AsciiArt.GoldenCase, slug: "python", piece: AsciiArt.Pieces.Python
end
