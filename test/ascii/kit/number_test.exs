defmodule Ascii.Kit.NumberTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ascii.Kit.Number

  doctest Number

  describe "fit/3" do
    test "as toFixed writes it, when that fits" do
      assert Number.fit(3.14159, 2, 5) == "3.14"
      assert Number.fit(-12, 1, 5) == "-12.0"
      assert Number.fit(100, 2, 6) == "100.00"
    end

    test "with fewer decimals before going compact" do
      assert Number.fit(12_345.67, 2, 7) == "12345.7"
      assert Number.fit(12_345.67, 2, 5) == "12346"
      assert Number.fit(-1234.5, 2, 5) == "-1235"
    end

    test "compact once no decimals fit" do
      assert Number.fit(3_020_463_651, 0, 5) == "3.02G"
      assert Number.fit(17_500_073, 2, 5) == "17.5M"
      assert Number.fit(16_600_000.0, 2, 7) == "16.6M"
      assert Number.fit(-2_500_000_000_000, 0, 6) == "-2.5T"
    end
  end

  describe "fit_all/3" do
    test "the same decimals for every number, as many as let them all fit" do
      assert Number.fit_all([1.25, 10.5, 100], 2, 6) == ["1.25", "10.50", "100.00"]
      assert Number.fit_all([1.25, 10.5, 100], 2, 5) == ["1.3", "10.5", "100.0"]
    end

    test "else in the largest one's unit, zeros they all end in dropped" do
      assert Number.fit_all([18_000_000, 17_000_000, 16_000_000], 2, 7) == ["18M", "17M", "16M"]
      assert Number.fit_all([1.5e6, -0.0001], 0, 6) == ["1.5M", "0.0M"]
    end

    test "else each compact, when no one unit fits them all" do
      assert Number.fit_all([999_999_999, 5], 0, 3) == ["1G", "5"]
    end
  end

  describe "compact/2" do
    test "the unit by size, decimals as the width leaves, trailing zeros dropped" do
      assert Number.compact(1_500, 4) == "1.5k"
      assert Number.compact(1_000, 4) == "1k"
      assert Number.compact(123_456, 4) == "123k"
      assert Number.compact(123_456, 6) == "123.5k"
      assert Number.compact(123_456, 7) == "123.46k"
      assert Number.compact(2.0e15, 3) == "2P"
      assert Number.compact(7.25e18, 5) == "7.25E"
    end

    test "rounding up to a thousand takes the next unit" do
      assert Number.compact(999_950, 4) == "1M"
      assert Number.compact(999_999_999, 5) == "1G"
      assert Number.compact(999.96, 3) == "1k"
    end

    test "below a thousand, decimals go; nothing is written as minus zero" do
      assert Number.compact(0.000012, 4) == "0"
      assert Number.compact(-0.000012, 4) == "0"
      assert Number.compact(12.345, 4) == "12.3"
    end

    test "too narrow for any form: as short as it can be" do
      assert Number.compact(-123_456_789, 2) == "-123M"
    end
  end

  property "fits the width whenever a form of the number can" do
    check all(
            x <-
              one_of([
                integer(-1_000_000_000_000_000..1_000_000_000_000_000),
                float(min: -1.0e15, max: 1.0e15)
              ]),
            digits <- integer(0..4),
            width <- integer(5..9)
          ) do
      s = Number.fit(x, digits, width)
      assert String.length(s) <= width, "#{inspect(x)} in #{width}: #{s}"
      assert s =~ ~r/^-?\d+(\.\d+)?[kMGTPE]?$/
    end
  end

  property "compact forms read back near the number" do
    check all(x <- float(min: -1.0e15, max: 1.0e15), abs(x) >= 1, width <- integer(5..9)) do
      s = Number.compact(x, width)
      [_, digits, suffix] = Regex.run(~r/^(-?[\d.]+)([kMGTPE]?)$/, s)
      scale = %{"" => 1, "k" => 1.0e3, "M" => 1.0e6, "G" => 1.0e9, "T" => 1.0e12, "P" => 1.0e15}

      {v, ""} = Float.parse(digits)
      back = v * scale[suffix]
      # Two significant digits at the least, in five cells.
      assert abs(back - x) <= abs(x) * 0.05 + 0.5, "#{x} read back as #{back} from #{s}"
    end
  end
end
