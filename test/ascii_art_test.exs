defmodule AsciiArtTest do
  use ExUnit.Case
  doctest AsciiArt

  test "greets the world" do
    assert AsciiArt.hello() == :world
  end
end
