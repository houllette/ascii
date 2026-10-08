defmodule AsciiArt.Int32Test do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AsciiArt.Int32

  # V8's answers, from tools/gen_js_math.mjs.
  @fixture "test/fixtures/js_math.json" |> File.read!() |> JSON.decode!() |> Map.fetch!("int32")

  defp double(hex) do
    <<x::float>> = <<String.to_integer(hex, 16)::64>>
    x
  end

  for op <- ~w(imul ushr sar shl bor bxor band) do
    test "#{op} matches JS" do
      fun = Function.capture(Int32, String.to_existing_atom(unquote(op)), 2)

      misses =
        for [a, b, want] <- @fixture[unquote(op)],
            fun.(a, b) != want,
            do: {a, b, want, fun.(a, b)}

      assert misses == [], "#{length(misses)} differ, first: #{inspect(Enum.take(misses, 3))}"
    end
  end

  test "to_int32 is `x | 0` and to_uint32 is `x >>> 0`, for integers and floats" do
    for {name, fun} <- [{"to_int32", &Int32.to_int32/1}, {"to_uint32", &Int32.to_uint32/1}] do
      misses = for [x, want] <- @fixture[name], fun.(double(x)) != want, do: {double(x), want}
      assert misses == [], "#{name}: #{inspect(Enum.take(misses, 3))}"
    end

    assert Int32.to_int32(0x80000000) == -0x80000000
    assert Int32.to_uint32(-1) == 0xFFFFFFFF
    assert Int32.to_int32(-3.7) == -3
  end

  test "mulberry32 gives the same sequence as the pieces' JS" do
    for [seed, want] <- @fixture["mulberry32"] do
      {got, _} =
        Enum.map_reduce(1..64, Int32.to_int32(seed), fn _, s ->
          {x, s} = Int32.mulberry32(s)
          {<<x::float>> |> Base.encode16(case: :lower), s}
        end)

      assert got == want, "seed #{seed}"
    end
  end

  property "umul and u32 agree with imul and >>> 0 on the unsigned values" do
    check all(a <- integer(-0x1_0000_0000..0x1_0000_0000), b <- integer(0..0xFFFFFFFF)) do
      assert Int32.umul(Int32.u32(a), b) == Int32.to_uint32(Int32.imul(a, b))
      assert Int32.u32(a) == Int32.to_uint32(a)
      assert Int32.u32(a + 0.5) == Int32.to_uint32(trunc(a + 0.5))
    end
  end

  property "results always fit in 32 bits" do
    check all(a <- integer(), b <- integer()) do
      for f <- [
            &Int32.imul/2,
            &Int32.bor/2,
            &Int32.bxor/2,
            &Int32.band/2,
            &Int32.shl/2,
            &Int32.sar/2
          ] do
        assert f.(a, b) in -0x80000000..0x7FFFFFFF
      end

      assert Int32.ushr(a, b) in 0..0xFFFFFFFF
    end
  end
end
