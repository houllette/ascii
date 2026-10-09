defmodule Ascii.Kit.Number do
  @moduledoc """
  Numbers written to fit a column: as given if they fit, with fewer
  decimals if that does, else compactly, in thousands (`k`), millions
  (`M`), billions (`G`), then `T`, `P` and `E`.

  This port's own, for readings bigger than upstream's columns were made
  for: a value of 3,020,463,651 in five cells is `3.02G` rather than
  `30204`, cut at the edge.

      iex> Ascii.Kit.Number.fit(3_020_463_651, 0, 5)
      "3.02G"
      iex> Ascii.Kit.Number.fit(1234.5678, 2, 7)
      "1234.57"
      iex> Ascii.Kit.Number.fit(42, 1, 5)
      "42.0"
  """

  alias Ascii.JSMath
  alias Ascii.Kit.Text

  @suffixes {"", "k", "M", "G", "T", "P", "E"}

  @doc """
  `x` in at most `width` characters: `x.toFixed(digits)` if it fits, else
  with as many of those decimals as fit, else `compact/2`.
  """
  @spec fit(x :: number(), digits :: non_neg_integer(), width :: pos_integer()) :: String.t()
  def fit(x, digits, width) do
    Enum.find_value(digits..0//-1, fn d ->
      s = JSMath.to_fixed(x, d)
      if Text.length(s) <= width, do: s
    end) || compact(x, width)
  end

  @doc """
  Numbers for one column or one line, each in at most `width` characters
  and all alike: with as many of `digits` decimals as let every one fit;
  else all in the unit of the largest, with as many decimals as fit but
  for zeros they all end in; else each `compact/2`.

      iex> Ascii.Kit.Number.fit_all([9999.5, 10_000], 2, 7)
      ["9999.5", "10000.0"]
      iex> Ascii.Kit.Number.fit_all([98_931_000, 98_930_000, 98_929_000], 2, 7)
      ["98.931M", "98.930M", "98.929M"]
      iex> Ascii.Kit.Number.fit_all([18_000_000, 17_500_000], 2, 7)
      ["18.0M", "17.5M"]
  """
  @spec fit_all(xs :: [number()], digits :: non_neg_integer(), width :: pos_integer()) ::
          [String.t()]
  def fit_all(xs, digits, width) do
    Enum.find_value(digits..0//-1, fn d ->
      texts = Enum.map(xs, &JSMath.to_fixed(&1, d))
      if Enum.all?(texts, &(Text.length(&1) <= width)), do: texts
    end) || alike(xs, width) || Enum.map(xs, &compact(&1, width))
  end

  defp alike([], _width), do: []

  defp alike(xs, width) do
    t = xs |> Enum.map(&tier(abs(&1))) |> Enum.max()
    suffix = elem(@suffixes, t)

    Enum.find_value(min(width, 15)..0//-1, fn d ->
      texts = Enum.map(xs, &unit(&1, t, d))

      if Enum.all?(texts, &(&1 != nil and Text.length(&1) + byte_size(suffix) <= width)),
        do: texts |> trim_alike() |> Enum.map(&(&1 <> suffix))
    end)
  end

  # `x` in units of 1000^t to d decimals, decimals kept and no suffix yet;
  # nil if that rounds up to a thousand of them and a larger unit follows.
  defp unit(x, t, d) do
    s = x |> Kernel./(:math.pow(1000, t)) |> JSMath.to_fixed(d) |> unsigned_zero()
    whole = s |> String.trim_leading("-") |> :binary.split(".") |> hd()
    if byte_size(whole) > 3 and t + 1 < tuple_size(@suffixes), do: nil, else: s
  end

  # Zeros that end every number's decimals dropped, and the point if none
  # are left: 18.000 and 17.500 are 18.0 and 17.5.
  defp trim_alike(texts) do
    cond do
      not Enum.all?(texts, &String.contains?(&1, ".")) ->
        texts

      Enum.all?(texts, &String.ends_with?(&1, "0")) ->
        texts |> Enum.map(&drop_last/1) |> trim_alike()

      Enum.all?(texts, &String.ends_with?(&1, ".")) ->
        Enum.map(texts, &drop_last/1)

      true ->
        texts
    end
  end

  defp drop_last(s), do: binary_part(s, 0, byte_size(s) - 1)

  defp unsigned_zero("-" <> digits = s),
    do: if(String.trim(digits, "0") in ["", "."], do: digits, else: s)

  defp unsigned_zero(s), do: s

  @doc """
  `x` in thousands, millions and on, with as many decimals as `width`
  leaves, trailing zeros dropped: `17.5M`, `-3.02G`, `999k`. A number too
  long for `width` however it is written comes as short as it can be.

      iex> Ascii.Kit.Number.compact(17_500_073, 5)
      "17.5M"
      iex> Ascii.Kit.Number.compact(-999_950, 4)
      "-1M"
      iex> Ascii.Kit.Number.compact(1_000_000, 7)
      "1M"
  """
  @spec compact(x :: number(), width :: pos_integer()) :: String.t()
  def compact(x, width) do
    tier = tier(abs(x))
    tiers = Enum.filter([tier, tier + 1], &(&1 < tuple_size(@suffixes)))

    forms =
      for t <- tiers, d <- min(width, 15)..0//-1, s = form(x, t, d), s != nil, do: s

    Enum.find(forms, &(Text.length(&1) <= width)) || Enum.min_by(forms, &Text.length/1)
  end

  defp tier(a) when a < 1000, do: 0
  defp tier(a), do: min(trunc(:math.log10(a) / 3), tuple_size(@suffixes) - 1)

  # `x` in units of 1000^t to d decimals, unless that rounds up to a
  # thousand of them and a larger unit follows, or down to none of them.
  defp form(x, t, d) do
    s = x |> Kernel./(:math.pow(1000, t)) |> JSMath.to_fixed(d) |> trim()
    whole = s |> String.trim_leading("-") |> :binary.split(".") |> hd()

    cond do
      byte_size(whole) > 3 and t + 1 < tuple_size(@suffixes) -> nil
      s == "0" and t > 0 -> nil
      true -> s <> elem(@suffixes, t)
    end
  end

  # Trailing zeros after the point dropped, and the point if nothing
  # follows it; a minus sign before nothing but zeros too.
  defp trim(s) do
    s =
      if String.contains?(s, "."),
        do: s |> String.trim_trailing("0") |> String.trim_trailing("."),
        else: s

    if s == "-0", do: "0", else: s
  end
end
