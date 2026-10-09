defmodule Ascii.Pieces.RustTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Rust
  use Ascii.GoldenCase, slug: "rust", piece: Ascii.Pieces.Rust
end
