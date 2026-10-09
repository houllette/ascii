defmodule Ascii.Pieces.PythonTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Python
  use Ascii.GoldenCase, slug: "python", piece: Ascii.Pieces.Python
end
