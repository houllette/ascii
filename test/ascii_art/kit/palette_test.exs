defmodule AsciiArt.Kit.PaletteTest do
  use ExUnit.Case, async: true

  alias AsciiArt.Kit.Palette

  @palette ["#000000", "#ffffff", "#ff0000"]

  test "rgb parses #rrggbb" do
    assert Palette.rgb("#ff8000") == {1.0, 128 / 255, 0.0}
    assert Palette.rgb255("#ff8000") == {255, 128, 0}
  end

  test "key packs each channel's step of the 32-step cube" do
    assert Palette.key(0, 0, 0) == 0
    assert Palette.key(1, 1, 1) == 32_767
    assert Palette.key(1, 0, 0) == 31 * 1024
    assert Palette.key(0.5, 0.5, 0.5) == 15 * 1024 + 15 * 32 + 15
  end

  test "nearest picks by weighted distance and remembers the first answer for a step" do
    lut = Palette.nearest_lut(@palette)
    assert Palette.cached(lut, Palette.key(0.9, 0.1, 0.1)) == :error
    {red, lut} = Palette.nearest(lut, 0.9, 0.1, 0.1)
    assert red == 2
    assert Palette.cached(lut, Palette.key(0.9, 0.1, 0.1)) == {:ok, 2}
    # Another colour in the same step gets the step's first answer, as upstream's cache gives it.
    assert {2, ^lut} = Palette.nearest(lut, 0.9 + 0.001, 0.1, 0.1)
  end
end
