defmodule Ascii.Pieces.FedoraTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Fedora
  use Ascii.GoldenCase, slug: "fedora", piece: Ascii.Pieces.Fedora
end
