defmodule Ascii.Kit.Text do
  @moduledoc """
  JS string operations, on code points.

  JS strings index UTF-16 code units, and every character a piece draws is in
  the BMP, where a code unit is a code point. These count and cut by code
  point, not by grapheme (as `String.length/1` does) nor by byte.
  """

  @doc "`s.length`."
  @spec length(s :: String.t()) :: non_neg_integer()
  def length(s), do: s |> String.to_charlist() |> Kernel.length()

  @doc "The characters of `s`, each a binary: `[...s]`."
  @spec chars(s :: String.t()) :: [String.t()]
  def chars(s), do: String.codepoints(s)

  @doc "`s.slice(from, to)`, negative indices counting from the end."
  @spec slice(s :: String.t(), from :: integer(), to :: integer() | nil) :: String.t()
  def slice(s, from, to \\ nil) do
    cps = String.to_charlist(s)
    n = Kernel.length(cps)
    from = index(from, n)
    to = if to == nil, do: n, else: index(to, n)
    if to > from, do: cps |> Enum.slice(from, to - from) |> List.to_string(), else: ""
  end

  defp index(i, n) when i < 0, do: max(n + i, 0)
  defp index(i, n), do: min(i, n)

  @doc "`s.padEnd(n, pad)`."
  @spec pad_end(s :: String.t(), n :: integer(), pad :: String.t()) :: String.t()
  def pad_end(s, n, pad \\ " "), do: s <> padding(n - __MODULE__.length(s), pad)

  @doc "`s.padStart(n, pad)`."
  @spec pad_start(s :: String.t(), n :: integer(), pad :: String.t()) :: String.t()
  def pad_start(s, n, pad \\ " "), do: padding(n - __MODULE__.length(s), pad) <> s

  defp padding(n, _pad) when n <= 0, do: ""
  defp padding(n, pad), do: pad |> String.duplicate(n) |> slice(0, n)

  @doc "`s.repeat(n)`, where a negative or fractional count is taken as JS would floor it."
  @spec repeat(s :: String.t(), n :: number()) :: String.t()
  def repeat(s, n), do: String.duplicate(s, max(floor(n), 0))
end
