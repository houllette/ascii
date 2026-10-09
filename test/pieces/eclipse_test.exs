defmodule Ascii.Pieces.EclipseTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Eclipse
  use Ascii.GoldenCase, slug: "eclipse", piece: Ascii.Pieces.Eclipse
end
