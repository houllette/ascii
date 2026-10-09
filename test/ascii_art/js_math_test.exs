defmodule AsciiArt.JSMathTest do
  use ExUnit.Case, async: true

  alias AsciiArt.JSMath

  # V8's answers, from tools/gen_js_math.mjs. Every double is its bits in hex,
  # so these compare exactly: one ulp off is a failure.
  @fixture "test/fixtures/js_math.json" |> File.read!() |> JSON.decode!()

  defp double(hex) do
    <<x::float>> = <<String.to_integer(hex, 16)::64>>
    x
  end

  defp bits(x) when is_float(x), do: x |> then(&<<&1::float>>) |> Base.encode16(case: :lower)
  defp bits(x) when is_integer(x), do: bits(x * 1.0)

  defp check(name, fun) do
    misses =
      for [_ | _] = row <- @fixture["math"][name],
          {args, [want]} = Enum.split(row, -1),
          got = apply(fun, Enum.map(args, &double/1)),
          bits(got) != want,
          do: {Enum.map(args, &double/1), double(want), got}

    assert misses == [],
           "#{name}: #{length(misses)} differ, first: #{inspect(Enum.take(misses, 3))}"
  end

  for name <- ~w(log1p cbrt sqrt) do
    test "#{name} matches V8 bit for bit" do
      check(unquote(name), &apply(JSMath, String.to_existing_atom(unquote(name)), [&1]))
    end
  end

  test "hypot matches V8, which scales and sums with Kahan's compensation" do
    check("hypot", &JSMath.hypot/2)
    check("hypot3", &JSMath.hypot/3)
  end

  test "mod is JS %: the remainder takes the dividend's sign" do
    check("fmod", &JSMath.mod/2)
    assert JSMath.mod(-7, 3) == -1
    assert JSMath.mod(7, -3) == 1
  end

  test "fround stores through a Float32Array" do
    check("fround", &JSMath.fround/1)
  end

  test "round is Math.round: half rounds up, toward +infinity" do
    # An integer, so JS's -0 for (-0.5, 0) compares as 0.
    misses =
      for [x, want] <- @fixture["math"]["round"],
          JSMath.round(double(x)) != double(want),
          do: {double(x), double(want)}

    assert misses == []
    assert JSMath.round(-2.5) == -2
    assert JSMath.round(2.5) == 3
    assert JSMath.round(0.49999999999999994) == 0
    assert is_integer(JSMath.round(1.7))
  end

  test "floor, ceil and trunc give integers to index with" do
    assert JSMath.floor(-1.5) == -2
    assert JSMath.ceil(-1.5) == -1
    assert JSMath.trunc(-1.5) == -1
    assert JSMath.floor(3) == 3
  end

  test "sign" do
    assert JSMath.sign(-0.3) == -1
    assert JSMath.sign(0.0) == 0
    assert JSMath.sign(4) == 1
  end

  test "u8 wraps like a Uint8Array and clamp_u8 clamps like a Uint8ClampedArray" do
    assert JSMath.u8(256) == 0
    assert JSMath.u8(-1) == 255
    assert JSMath.u8(3.9) == 3
    assert JSMath.u8(-3.9) == 253
    assert JSMath.clamp_u8(300) == 255
    assert JSMath.clamp_u8(-4) == 0
    assert JSMath.clamp_u8(2.5) == 2
    assert JSMath.clamp_u8(3.5) == 4
    assert JSMath.clamp_u8(3.2) == 3
  end

  test "i8, i16 and u16 wrap like their typed arrays" do
    assert JSMath.i8(128) == -128
    assert JSMath.i8(-129) == 127
    assert JSMath.i16(32_768) == -32_768
    assert JSMath.u16(-1) == 65_535
    assert JSMath.i16(-3.7) == -3
  end

  test "to_fixed matches Number.prototype.toFixed" do
    misses =
      for [hex, digits, want] <- @fixture["to_fixed"],
          got = JSMath.to_fixed(double(hex), digits),
          got != want,
          do: {double(hex), digits, want, got}

    assert misses == [], "#{length(misses)} differ, first: #{inspect(Enum.take(misses, 5))}"
  end

  test "to_string matches String(number)" do
    misses =
      for [hex, want] <- @fixture["to_string"],
          got = JSMath.to_string(double(hex)),
          got != want,
          do: {double(hex), want, got}

    assert misses == [], "#{length(misses)} differ, first: #{inspect(Enum.take(misses, 5))}"
    assert JSMath.to_string(42) == "42"
    assert JSMath.to_string(-0.0) == "0"
  end

  test "where JS answers with Infinity or NaN, these raise, as :math does" do
    assert_raise ArithmeticError, fn -> JSMath.log1p(-1) end
    assert_raise ArithmeticError, fn -> JSMath.log1p(-2) end
    assert_raise ArithmeticError, fn -> JSMath.sqrt(-1) end

    # The pieces call :math for the rest, and guard these cases as upstream
    # relies on them. Evaluate at runtime so OTP 27 does not warn about
    # these deliberately invalid constant calls during compilation.
    for {function, args} <- [
          {:exp, [710]},
          {:log, [0]},
          {:log, [-1]},
          {:pow, [0, -1]},
          {:pow, [-2, 0.5]},
          {:asin, [1.5]}
        ] do
      assert_raise ArithmeticError, fn -> apply(:math, function, args) end
    end
  end

  test ":math.exp underflows to zero as JS does" do
    assert :math.exp(-800) == 0.0
  end
end
