defmodule Ascii.Int32 do
  @moduledoc """
  JavaScript's 32-bit integer operators.

  JS converts both operands of `|`, `&`, `^`, `<<`, `>>` and `>>>` to 32 bits
  and gives a signed 32-bit result (unsigned for `>>>`); `Math.imul`
  multiplies modulo 2^32. Elixir integers never overflow, so the pieces' hashes
  and PRNGs go through these functions rather than `Bitwise` directly.

  Every function accepts any integer, or a float, which is truncated first
  as JS's ToInt32 does.
  """
  import Bitwise, only: [bsl: 2, bsr: 2]

  @compile {:inline, to_int32: 1, to_uint32: 1, shift: 1}

  @typedoc "A signed 32-bit integer."
  @type int32 :: -0x80000000..0x7FFFFFFF
  @typedoc "An unsigned 32-bit integer."
  @type uint32 :: 0..0xFFFFFFFF

  @doc "`x | 0`."
  @spec to_int32(x :: number()) :: int32()
  def to_int32(x) when is_integer(x) do
    y = Bitwise.band(x, 0xFFFFFFFF)
    if y >= 0x80000000, do: y - 0x100000000, else: y
  end

  def to_int32(x) when is_float(x), do: to_int32(trunc(x))

  @doc "`x >>> 0`."
  @spec to_uint32(x :: number()) :: uint32()
  def to_uint32(x) when is_integer(x), do: Bitwise.band(x, 0xFFFFFFFF)
  def to_uint32(x) when is_float(x), do: Bitwise.band(trunc(x), 0xFFFFFFFF)

  defp shift(n) when is_integer(n), do: Bitwise.band(n, 31)
  defp shift(n), do: Bitwise.band(trunc(n), 31)

  @doc "`Math.imul(a, b)`, without building a 64-bit product."
  @spec imul(a :: number(), b :: number()) :: int32()
  def imul(a, b) do
    a = to_uint32(a)
    b = to_uint32(b)
    lo = Bitwise.band(a, 0xFFFF) * b
    hi = Bitwise.band(bsr(a, 16) * Bitwise.band(b, 0xFFFF), 0xFFFF)
    to_int32(lo + bsl(hi, 16))
  end

  @doc "`a >>> n`."
  @spec ushr(a :: number(), n :: number()) :: uint32()
  def ushr(a, n), do: bsr(to_uint32(a), shift(n))

  @doc "`a >> n`."
  @spec sar(a :: number(), n :: number()) :: int32()
  def sar(a, n), do: bsr(to_int32(a), shift(n))

  @doc "`a << n`."
  @spec shl(a :: number(), n :: number()) :: int32()
  def shl(a, n), do: to_int32(bsl(to_uint32(a), shift(n)))

  @doc "`a | b`."
  @spec bor(a :: number(), b :: number()) :: int32()
  def bor(a, b), do: Bitwise.bor(to_int32(a), to_int32(b))

  @doc "`a ^ b`."
  @spec bxor(a :: number(), b :: number()) :: int32()
  def bxor(a, b), do: Bitwise.bxor(to_int32(a), to_int32(b))

  @doc "`a & b`."
  @spec band(a :: number(), b :: number()) :: int32()
  def band(a, b), do: Bitwise.band(to_int32(a), to_int32(b))

  @doc """
  `x >>> 0` for a value already known to be an integer or a float, without
  the sign handling: the fast path for hashes, which stay unsigned.
  """
  @spec u32(x :: number()) :: uint32()
  def u32(x) when is_integer(x), do: Bitwise.band(x, 0xFFFFFFFF)
  def u32(x), do: Bitwise.band(trunc(x), 0xFFFFFFFF)

  @doc """
  `Math.imul(a, b) >>> 0` for two unsigned 32-bit integers.

  A hash that only ever feeds `^`, `>>>`, `+` and `Math.imul` with its
  intermediate values can work in unsigned arithmetic throughout, since all
  four agree modulo 2^32 whatever the signs; this skips `imul/2`'s
  conversions and is several times faster.
  """
  @spec umul(a :: uint32(), b :: uint32()) :: uint32()
  def umul(a, b) do
    Bitwise.band(
      Bitwise.band(a, 0xFFFF) * b +
        bsl(Bitwise.band(bsr(a, 16) * Bitwise.band(b, 0xFFFF), 0xFFFF), 16),
      0xFFFFFFFF
    )
  end

  @doc """
  One draw from mulberry32, the PRNG most pieces seed: given the state, the
  next number in [0, 1) and the next state. Start from `to_int32(seed)`.

      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  """
  @spec mulberry32(state :: int32()) :: {float(), int32()}
  def mulberry32(state) do
    a = to_int32(state + 0x6D2B79F5)
    t = imul(Bitwise.bxor(a, bsr(to_uint32(a), 15)), Bitwise.bor(1, a))

    t =
      Bitwise.bxor(
        to_int32(t + imul(Bitwise.bxor(t, bsr(to_uint32(t), 7)), Bitwise.bor(61, t))),
        t
      )

    {to_uint32(Bitwise.bxor(t, bsr(to_uint32(t), 14))) / 4_294_967_296, a}
  end
end
