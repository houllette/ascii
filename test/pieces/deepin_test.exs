defmodule Ascii.Pieces.DeepinTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Deepin
  use Ascii.GoldenCase, slug: "deepin", piece: Ascii.Pieces.Deepin
end
