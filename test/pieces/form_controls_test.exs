defmodule AsciiArt.Pieces.FormControlsTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.FormControls
  use AsciiArt.GoldenCase, slug: "form-controls", piece: AsciiArt.Pieces.FormControls
end
