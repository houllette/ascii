defmodule Ascii.Kit.Ramp do
  @moduledoc """
  Shading ramps, light to dense, and their flip on paper.

  On a dark page a dense character is bright; on paper (`env.paper`) it is
  dark, so shaded pieces read their ramp from the other end. A ramp here is
  a tuple of one-character binaries, made once from upstream's string.
  """

  @doc "A ramp from upstream's string: `\".,-~:;=!*#$@\"`."
  @spec new(chars :: String.t()) :: tuple()
  def new(chars), do: chars |> String.codepoints() |> List.to_tuple()

  @doc "The `i`-th character, counted from the dense end on paper."
  @spec at(ramp :: tuple(), i :: non_neg_integer(), paper :: boolean()) :: String.t()
  def at(ramp, i, false), do: elem(ramp, i)
  def at(ramp, i, true), do: elem(ramp, tuple_size(ramp) - 1 - i)
end
