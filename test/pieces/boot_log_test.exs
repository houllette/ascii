defmodule AsciiArt.Pieces.BootLogTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.BootLog
  use AsciiArt.GoldenCase, slug: "boot-log", piece: AsciiArt.Pieces.BootLog
end
