defmodule Ascii.Kit.Hash do
  @moduledoc """
  The integer hashes that many upstream pieces share, word for word.

  Each returns upstream's value: a float in [0, 1) or, for `distro/3`, the
  unsigned integer. Arguments may be integers or floats (truncated, as JS's
  `Math.imul` and `| 0` truncate). They run in unsigned arithmetic with the
  multiply inlined, since `^`, `>>>`, `+` and `Math.imul` agree modulo 2^32
  whatever the signs; that makes them several times faster than the same
  steps through `Ascii.Int32`, which matters for scenes that hash tens of
  thousands of times a frame.

  A piece whose hash is not one of these writes its own with
  `Ascii.Int32`.
  """

  import Bitwise

  @compile {:inline, u32: 1, umul: 2}

  defp u32(x) when is_integer(x), do: band(x, 0xFFFFFFFF)
  defp u32(x), do: band(trunc(x), 0xFFFFFFFF)

  defp umul(a, b),
    do:
      band(band(a, 0xFFFF) * b + bsl(band(bsr(a, 16) * band(b, 0xFFFF), 0xFFFF), 16), 0xFFFFFFFF)

  @doc """
  The scenes' hash (night-coast, alpine-dawn and every other scene, and
  dissolve):

      let h = Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263);
      h = Math.imul(h ^ (h >>> 13), 1274126177);
      return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  """
  @spec scene(x :: number(), y :: number()) :: float()
  def scene(x, y) do
    h = band(umul(u32(x), 374_761_393) + umul(u32(y), 668_265_263), 0xFFFFFFFF)
    h = umul(bxor(h, bsr(h, 13)), 1_274_126_177)
    bxor(h, bsr(h, 16)) / 4_294_967_296
  end

  @doc """
  A murmur-style hash of two (aurora, doom-fire, lightning, saptarishi,
  aquarium, campfire, cherry-blossom):

      let h = Math.imul(x, 0x27d4eb2d) ^ Math.imul(y, 0x165667b1);
      h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
      h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
      return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  """
  @spec murmur(x :: number(), y :: number()) :: float()
  def murmur(x, y) do
    h = bxor(umul(u32(x), 0x27D4EB2D), umul(u32(y), 0x165667B1))
    h = umul(bxor(h, bsr(h, 15)), 0x85EBCA6B)
    h = umul(bxor(h, bsr(h, 13)), 0xC2B2AE35)
    bxor(h, bsr(h, 16)) / 4_294_967_296
  end

  @doc """
  The same of three (sunrise, tv-static, wind):

      let h = Math.imul(a, 0x27d4eb2d) ^ Math.imul(b, 0x165667b1) ^ Math.imul(c, 0x2545f491);

  then as `murmur/2`.
  """
  @spec murmur(a :: number(), b :: number(), c :: number()) :: float()
  def murmur(a, b, c) do
    h = bxor(bxor(umul(u32(a), 0x27D4EB2D), umul(u32(b), 0x165667B1)), umul(u32(c), 0x2545F491))
    h = umul(bxor(h, bsr(h, 15)), 0x85EBCA6B)
    h = umul(bxor(h, bsr(h, 13)), 0xC2B2AE35)
    bxor(h, bsr(h, 16)) / 4_294_967_296
  end

  @doc """
  One round of the murmur-style hash (lighthouse, train, windmill,
  fractal-tree, landscape):

      let h = Math.imul(x, 0x27d4eb2d) ^ Math.imul(y, 0x165667b1);
      h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
      return ((h ^ (h >>> 13)) >>> 0) / 4294967296;
  """
  @spec short(x :: number(), y :: number()) :: float()
  def short(x, y) do
    h = bxor(umul(u32(x), 0x27D4EB2D), umul(u32(y), 0x165667B1))
    h = umul(bxor(h, bsr(h, 15)), 0x85EBCA6B)
    bxor(h, bsr(h, 13)) / 4_294_967_296
  end

  @doc """
  The distros' scan noise, as an unsigned integer:

      let h = Math.imul(x, 73856093) ^ Math.imul(y, 19349663) ^ Math.imul(k, 83492791);
      h = Math.imul(h ^ (h >>> 13), 1274126177);
      return (h ^ (h >>> 16)) >>> 0;
  """
  @spec distro(x :: number(), y :: number(), k :: number()) :: non_neg_integer()
  def distro(x, y, k) do
    h = bxor(bxor(umul(u32(x), 73_856_093), umul(u32(y), 19_349_663)), umul(u32(k), 83_492_791))
    h = umul(bxor(h, bsr(h, 13)), 1_274_126_177)
    bxor(h, bsr(h, 16))
  end
end
