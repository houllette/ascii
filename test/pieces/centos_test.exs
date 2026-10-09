defmodule Ascii.Pieces.CentosTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Centos
  use Ascii.GoldenCase, slug: "centos", piece: Ascii.Pieces.Centos
end
