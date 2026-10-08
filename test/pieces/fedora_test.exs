defmodule AsciiArt.Pieces.FedoraTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Fedora
  use AsciiArt.GoldenCase, slug: "fedora", piece: AsciiArt.Pieces.Fedora
end
