defmodule AsciiArt.Kit.HashTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AsciiArt.Int32
  alias AsciiArt.Kit.Hash

  # The JS, transcribed step by step through Int32's checked operators.
  defp finish(h, shift), do: Int32.to_uint32(Int32.bxor(h, Int32.ushr(h, shift))) / 4_294_967_296

  defp scene(x, y) do
    h = Int32.imul(Int32.to_int32(x), 374_761_393) + Int32.imul(Int32.to_int32(y), 668_265_263)
    finish(Int32.imul(Int32.bxor(h, Int32.ushr(h, 13)), 1_274_126_177), 16)
  end

  defp rounds(h, two?) do
    h = Int32.imul(Int32.bxor(h, Int32.ushr(h, 15)), 0x85EBCA6B)

    if two?,
      do: finish(Int32.imul(Int32.bxor(h, Int32.ushr(h, 13)), 0xC2B2AE35), 16),
      else: finish(h, 13)
  end

  defp pair(x, y), do: Int32.bxor(Int32.imul(x, 0x27D4EB2D), Int32.imul(y, 0x165667B1))
  defp murmur(x, y), do: rounds(pair(x, y), true)
  defp short(x, y), do: rounds(pair(x, y), false)
  defp murmur(a, b, c), do: rounds(Int32.bxor(pair(a, b), Int32.imul(c, 0x2545F491)), true)

  defp distro(x, y, k) do
    h =
      Int32.bxor(
        Int32.bxor(Int32.imul(x, 73_856_093), Int32.imul(y, 19_349_663)),
        Int32.imul(k, 83_492_791)
      )

    h = Int32.imul(Int32.bxor(h, Int32.ushr(h, 13)), 1_274_126_177)
    Int32.to_uint32(Int32.bxor(h, Int32.ushr(h, 16)))
  end

  defp num, do: one_of([integer(), float(min: -1.0e9, max: 1.0e9)])

  property "each hash is its JS, step for step" do
    check all(x <- num(), y <- num(), z <- num(), max_runs: 500) do
      assert Hash.scene(x, y) == scene(x, y)
      assert Hash.murmur(x, y) == murmur(x, y)
      assert Hash.short(x, y) == short(x, y)
      assert Hash.murmur(x, y, z) == murmur(x, y, z)
      assert Hash.distro(x, y, z) == distro(x, y, z)
    end
  end

  test "values computed by Node" do
    assert Hash.scene(3, 7) == 0.06072395155206323
    assert Hash.scene(-123_456, 98_765.7) == 0.7881029630079865
    assert Hash.murmur(5, -9) == 0.05699266213923693
    assert Hash.murmur(2_147_483_653, 17.9) == 0.5976723309140652
  end
end
