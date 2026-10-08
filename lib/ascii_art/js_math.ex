defmodule AsciiArt.JSMath do
  @moduledoc """
  JavaScript's number semantics where they differ from Elixir's.

  `Math.round` (halves up, toward +infinity), `%` (the dividend's sign),
  `Math.fround`, typed-array stores (`u8/1`, `clamp_u8/1`, `i8/1`, ...),
  `Number.prototype.toFixed` and `String(number)`, V8's `Math.hypot` (which
  scales and sums with Kahan's compensation), and two functions `:math` does
  not have, `Math.cbrt` and `Math.log1p`, as fdlibm computes them. All of
  these agree with V8 bit for bit.

  For `Math.sin`, `Math.exp`, `Math.pow` and the other transcendental
  functions the pieces call `:math` directly. It uses the platform's libm,
  which can differ from V8's fdlibm in the last bit for a few percent of
  inputs; a character rarely sits that close to a threshold, and every
  piece's golden frames still match upstream's (see PORTING.md).

  Erlang floats have no infinity and no NaN. Where JS would answer with one,
  these functions raise `ArithmeticError`, as `:math` and Erlang arithmetic
  do, and the pieces guard such cases where upstream relies on them.

  Rounding functions (`round/1`, `floor/1`, `ceil/1`, `trunc/1`) return
  integers, which is what the pieces index with.
  """
  import Bitwise

  @compile {:inline, hi: 1, from_words: 2, set_hi: 2, float: 1}

  # -- bits ------------------------------------------------------------------

  defp float(x) when is_float(x), do: x
  defp float(x) when is_integer(x), do: x * 1.0

  # The high word, signed.
  defp hi(x) do
    <<h::signed-32, _::32>> = <<x::float>>
    h
  end

  defp from_words(h, l) do
    <<x::float>> = <<h::32, l::32>>
    x
  end

  defp set_hi(x, h) do
    <<_::32, l::32>> = <<x::float>>
    <<y::float>> = <<h::32, l::32>>
    y
  end

  defp nan!(name), do: raise(ArithmeticError, "#{name} is NaN in JS")
  defp infinity!(name), do: raise(ArithmeticError, "#{name} is Infinity in JS")

  # -- rounding --------------------------------------------------------------

  @doc "`Math.round`: halves round up, toward +infinity. Returns an integer."
  @spec round(x :: number()) :: integer()
  def round(x) when is_integer(x), do: x

  def round(x) when is_float(x) do
    c = Kernel.ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end

  @doc "`Math.floor`, as an integer."
  @spec floor(x :: number()) :: integer()
  def floor(x), do: Kernel.floor(x)

  @doc "`Math.ceil`, as an integer."
  @spec ceil(x :: number()) :: integer()
  def ceil(x), do: Kernel.ceil(x)

  @doc "`Math.trunc`, as an integer."
  @spec trunc(x :: number()) :: integer()
  def trunc(x), do: Kernel.trunc(x)

  @doc "`Math.sign`: -1, 0 or 1."
  @spec sign(x :: number()) :: -1 | 0 | 1
  def sign(x) when x > 0, do: 1
  def sign(x) when x < 0, do: -1
  def sign(_), do: 0

  @doc """
  JS `%`: the remainder of truncated division, with the dividend's sign
  (C's `fmod`). Integers stay integers.
  """
  @spec mod(a :: number(), b :: number()) :: number()
  def mod(a, b) when is_integer(a) and is_integer(b), do: rem(a, b)
  def mod(a, b), do: :math.fmod(float(a), float(b))

  @doc "`Math.fround`: the nearest single-precision value, as a `Float32Array` stores it."
  @spec fround(x :: number()) :: float()
  def fround(x) do
    <<y::float-32>> = <<x::float-32>>
    y
  end

  @doc "A write to a `Uint8Array`: truncated, then wrapped modulo 256."
  @spec u8(x :: number()) :: 0..255
  def u8(x), do: band(Kernel.trunc(x), 0xFF)

  @doc "A write to a `Uint8ClampedArray`: clamped to 0..255, halves to even."
  @spec clamp_u8(x :: number()) :: 0..255
  def clamp_u8(x) when x <= 0, do: 0
  def clamp_u8(x) when x >= 255, do: 255
  def clamp_u8(x) when is_integer(x), do: x

  def clamp_u8(x) do
    f = Kernel.floor(x)

    cond do
      x - f > 0.5 -> f + 1
      x - f < 0.5 -> f
      rem(f, 2) == 0 -> f
      true -> f + 1
    end
  end

  @doc "A write to an `Int8Array`."
  @spec i8(x :: number()) :: -128..127
  def i8(x), do: wrap(Kernel.trunc(x), 0xFF, 0x80)

  @doc "A write to an `Int16Array`."
  @spec i16(x :: number()) :: -32_768..32_767
  def i16(x), do: wrap(Kernel.trunc(x), 0xFFFF, 0x8000)

  @doc "A write to a `Uint16Array`."
  @spec u16(x :: number()) :: 0..65_535
  def u16(x), do: band(Kernel.trunc(x), 0xFFFF)

  defp wrap(n, mask, sign) do
    v = band(n, mask)
    if v >= sign, do: v - mask - 1, else: v
  end

  # -- algebraic ------------------------------------------------------------

  @doc "`Math.sqrt`, exactly rounded on every platform."
  @spec sqrt(x :: number()) :: float()
  def sqrt(x) when x < 0, do: nan!("sqrt of a negative")
  def sqrt(x), do: :math.sqrt(x)

  @doc """
  `Math.hypot`, as V8 computes it: each term scaled by the largest and summed
  with Kahan's compensation. Not the same bits as `sqrt(a*a + b*b)`.
  """
  @spec hypot(a :: number(), b :: number()) :: float()
  def hypot(a, b) do
    a = Kernel.abs(float(a))
    b = Kernel.abs(float(b))
    max = if b > a, do: b, else: a

    if max == 0 do
      0.0
    else
      # With two terms the compensation is still zero when it would apply.
      x = a / max
      y = b / max
      :math.sqrt(x * x + y * y) * max
    end
  end

  @doc "`Math.hypot` of three numbers: `hypot_list/1`'s steps, unrolled."
  @spec hypot(a :: number(), b :: number(), c :: number()) :: float()
  def hypot(a, b, c) do
    a = Kernel.abs(float(a))
    b = Kernel.abs(float(b))
    c = Kernel.abs(float(c))
    max = a |> max(b) |> max(c)

    if max == 0 do
      0.0
    else
      # The first term's compensation is zero, and so is the first sum's.
      x = a / max
      y = b / max
      z = c / max
      s1 = x * x
      s2 = s1 + y * y
      comp = s2 - s1 - y * y
      :math.sqrt(s2 + (z * z - comp)) * max
    end
  end

  @doc "`Math.hypot` of any count of numbers."
  @spec hypot_list(xs :: [number()]) :: float()
  def hypot_list(xs) do
    abs = Enum.map(xs, &Kernel.abs(float(&1)))
    max = Enum.max(abs, fn -> 0.0 end)

    if max == 0 do
      0.0
    else
      {sum, _} =
        Enum.reduce(abs, {0.0, 0.0}, fn a, {sum, comp} ->
          n = a / max
          summand = n * n - comp
          pre = sum + summand
          {pre, pre - sum - summand}
        end)

      :math.sqrt(sum) * max
    end
  end

  @b1 715_094_163
  @b2 696_219_795
  @cbrt_p0 1.87595182427177009643
  @cbrt_p1 -1.88497979543377169875
  @cbrt_p2 1.621429720105354466140
  @cbrt_p3 -0.758397934778766047437
  @cbrt_p4 0.145996192886612446982

  @doc "`Math.cbrt` (fdlibm)."
  @spec cbrt(x :: number()) :: float()
  def cbrt(x) do
    x = float(x)
    <<hxu::32, low::32>> = <<x::float>>
    sign = band(hxu, 0x80000000)
    hx = bxor(hxu, sign)

    t =
      cond do
        hx < 0x00100000 and bor(hx, low) == 0 ->
          nil

        hx < 0x00100000 ->
          t = from_words(0x43500000, 0) * x
          <<high::32, _::32>> = <<t::float>>
          from_words(bor(sign, div(band(high, 0x7FFFFFFF), 3) + @b2), 0)

        true ->
          from_words(bor(sign, div(hx, 3) + @b1), 0)
      end

    if t == nil, do: x, else: cbrt_newton(x, t)
  end

  defp cbrt_newton(x, t) do
    r = t * t * (t / x)
    t = t * (@cbrt_p0 + r * (@cbrt_p1 + r * @cbrt_p2) + r * r * r * (@cbrt_p3 + r * @cbrt_p4))
    <<bits::64>> = <<t::float>>
    <<t::float>> = <<band(bits + 0x80000000, 0xFFFFFFFFC0000000)::64>>
    s = t * t
    r = x / s
    w = t + t
    r = (r - t) / (w + r)
    t + t * r
  end

  # -- log1p -----------------------------------------------------------------
  #
  # `:math` has no log1p, and log(1 + x) loses what matters near 0.

  @ln2_hi 6.93147180369123816490e-01
  @ln2_lo 1.90821492927058770002e-10
  @lg1 6.666666666666735130e-01
  @lg2 3.999999999940941908e-01
  @lg3 2.857142874366239149e-01
  @lg4 2.222219843214978396e-01
  @lg5 1.818357216161805012e-01
  @lg6 1.531383769920937332e-01
  @lg7 1.479819860511658591e-01

  @doc "`Math.log1p` (fdlibm)."
  @spec log1p(x :: number()) :: float()
  def log1p(x) do
    x = float(x)
    hx = hi(x)
    ax = band(hx, 0x7FFFFFFF)

    cond do
      hx < 0x3FDA827A and ax >= 0x3FF00000 and x == -1.0 -> infinity!("log1p(-1)")
      hx < 0x3FDA827A and ax >= 0x3FF00000 -> nan!("log1p below -1")
      hx < 0x3FDA827A and ax < 0x3C900000 -> x
      hx < 0x3FDA827A and ax < 0x3E200000 -> x - x * x * 0.5
      hx < 0x3FDA827A and (hx > 0 or hx <= -0x402D413C) -> log1p_poly(x, 0, 1, 0.0)
      true -> log1p_reduce(x, hx)
    end
  end

  defp log1p_reduce(x, hx) do
    {u, hu, k, c} =
      if hx < 0x43400000 do
        u = 1.0 + x
        hu = hi(u)
        k = bsr(hu, 20) - 1023
        c = if k > 0, do: 1.0 - (u - x), else: x - (u - 1.0)
        {u, hu, k, c / u}
      else
        {x, hi(x), bsr(hi(x), 20) - 1023, 0.0}
      end

    hu = band(hu, 0x000FFFFF)

    {u, k, hu} =
      if hu < 0x6A09E,
        do: {set_hi(u, bor(hu, 0x3FF00000)), k, hu},
        else: {set_hi(u, bor(hu, 0x3FE00000)), k + 1, bsr(0x00100000 - hu, 2)}

    log1p_poly(u - 1.0, k, hu, c)
  end

  defp log1p_poly(f, k, hu, c) do
    hfsq = 0.5 * f * f

    cond do
      hu == 0 and f == 0 and k == 0 ->
        0.0

      hu == 0 and f == 0 ->
        c = c + k * @ln2_lo
        k * @ln2_hi + c

      hu == 0 ->
        r = hfsq * (1.0 - 0.66666666666666666 * f)
        if k == 0, do: f - r, else: k * @ln2_hi - (r - (k * @ln2_lo + c) - f)

      true ->
        s = f / (2.0 + f)
        z = s * s
        r = z * (@lg1 + z * (@lg2 + z * (@lg3 + z * (@lg4 + z * (@lg5 + z * (@lg6 + z * @lg7))))))

        if k == 0,
          do: f - (hfsq - s * (hfsq + r)),
          else: k * @ln2_hi - (hfsq - (s * (hfsq + r) + (k * @ln2_lo + c)) - f)
    end
  end

  # -- text ------------------------------------------------------------------

  @doc """
  `Number.prototype.toFixed`: rounds the exact binary value, halves away from
  zero, which is not what `:erlang.float_to_binary/2` does on a tie.
  """
  @spec to_fixed(x :: number(), digits :: non_neg_integer()) :: String.t()
  def to_fixed(x, digits) when x < 0, do: "-" <> to_fixed(-x, digits)
  def to_fixed(x, _digits) when x >= 1.0e21, do: __MODULE__.to_string(x)

  def to_fixed(x, digits) when is_integer(x),
    do: Integer.to_string(x) <> if(digits > 0, do: "." <> String.duplicate("0", digits), else: "")

  def to_fixed(x, digits) do
    {m, e} = mantissa_exponent(x)
    scale = Integer.pow(10, digits)

    n =
      if e >= 0,
        do: bsl(m, e) * scale,
        else: div(2 * m * scale + bsl(1, -e), bsl(1, -e + 1))

    s = Integer.to_string(n)

    if digits == 0 do
      s
    else
      s = String.pad_leading(s, digits + 1, "0")
      {whole, frac} = String.split_at(s, -digits)
      whole <> "." <> frac
    end
  end

  defp mantissa_exponent(x) do
    <<_::1, e::11, f::52>> = <<x::float>>
    if e == 0, do: {f, -1074}, else: {bor(f, bsl(1, 52)), e - 1075}
  end

  @doc "`String(x)` for a number: the shortest digits that read back as `x`, laid out as JS does."
  @spec to_string(x :: number()) :: String.t()
  def to_string(x) when is_integer(x), do: Integer.to_string(x)
  def to_string(x) when x == 0, do: "0"
  def to_string(x) when x < 0, do: "-" <> __MODULE__.to_string(-x)

  def to_string(x) do
    {digits, n} = shortest(x)
    k = byte_size(digits)

    cond do
      k <= n and n <= 21 ->
        digits <> String.duplicate("0", n - k)

      0 < n and n <= 21 ->
        {a, b} = String.split_at(digits, n)
        a <> "." <> b

      -6 < n and n <= 0 ->
        "0." <> String.duplicate("0", -n) <> digits

      true ->
        exp = n - 1
        sign = if exp < 0, do: "-", else: "+"
        {d, rest} = String.split_at(digits, 1)
        mant = if rest == "", do: d, else: d <> "." <> rest
        mant <> "e" <> sign <> Integer.to_string(Kernel.abs(exp))
    end
  end

  # The shortest round-tripping digits of a positive float, with the decimal
  # point n places from their left.
  defp shortest(x) do
    s = :erlang.float_to_binary(x, [:short])

    {mant, exp} =
      case String.split(s, "e") do
        [m, e] -> {m, String.to_integer(e)}
        [m] -> {m, 0}
      end

    {int, frac} =
      case String.split(mant, ".") do
        [i, f] -> {i, f}
        [i] -> {i, ""}
      end

    all = int <> frac
    lead = byte_size(all) - byte_size(String.trim_leading(all, "0"))
    digits = all |> String.trim_leading("0") |> String.trim_trailing("0")
    {digits, byte_size(int) + exp - lead}
  end
end
