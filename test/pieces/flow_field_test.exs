defmodule Ascii.Pieces.FlowFieldTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.FlowField
  use Ascii.GoldenCase, slug: "flow-field", piece: Ascii.Pieces.FlowField
end
