defmodule AsciiArt.Pieces.RustTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Rust
  use AsciiArt.GoldenCase, slug: "rust", piece: AsciiArt.Pieces.Rust
end
