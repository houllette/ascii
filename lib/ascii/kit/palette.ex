defmodule Ascii.Kit.Palette do
  @moduledoc """
  Colours: `#rrggbb` parsing and the scenes' nearest-palette lookup.

  Every upstream scene shades each cell as an RGB colour, then draws it in
  the palette colour nearest that hue, by a weighted distance, cached on a
  32-step colour cube. The cache is upstream's `Uint8Array(32768)`: the
  first colour to land in a step of the cube decides that step's answer for
  every later one. So it is part of a scene's state, filled in the same order
  as upstream fills it, and two colours in one step can get a different
  answer depending on which came first.
  """

  import Bitwise

  @typedoc """
  The cache: the palette as RGB in 0..1, and the answers so far, keyed by
  `key/3`. The shape is part of this module's contract: a scene's frame may
  look an answer up in `answers` itself (and compute the key inline), since a
  call to another module cannot be inlined into a loop over 20,000 cells.
  """
  @type lut :: {palette :: tuple(), answers :: %{non_neg_integer() => non_neg_integer()}}

  @doc "`#rrggbb` as `{r, g, b}` in 0..1."
  @spec rgb(hex :: String.t()) :: {float(), float(), float()}
  def rgb(<<"#", r::binary-size(2), g::binary-size(2), b::binary-size(2)>>),
    do:
      {String.to_integer(r, 16) / 255, String.to_integer(g, 16) / 255,
       String.to_integer(b, 16) / 255}

  @doc "`#rrggbb` as `{r, g, b}` in 0..255."
  @spec rgb255(hex :: String.t()) :: {byte(), byte(), byte()}
  def rgb255(<<"#", r::binary-size(2), g::binary-size(2), b::binary-size(2)>>),
    do: {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}

  @doc "An empty cache for a palette."
  @spec nearest_lut(palette :: [String.t()]) :: lut()
  def nearest_lut(palette), do: {palette |> Enum.map(&rgb/1) |> List.to_tuple(), %{}}

  @doc """
  A colour's step of the 32-step cube, as upstream packs it:
  `min(31, trunc(v * 31.99))` a channel, red in the high bits.
  """
  @spec key(r :: number(), g :: number(), b :: number()) :: 0..32_767
  def key(r, g, b), do: bsl(step(r), 10) ||| bsl(step(g), 5) ||| step(b)

  @doc "The cached answer for a key, if a colour in that step has been looked up."
  @spec cached(lut :: lut(), key :: non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  def cached({_palette, answers}, key), do: Map.fetch(answers, key)

  @doc "The palette index nearest `r`, `g`, `b` (each in 0..1), and the cache."
  @spec nearest(lut :: lut(), r :: number(), g :: number(), b :: number()) ::
          {non_neg_integer(), lut()}
  def nearest({p, answers} = lut, r, g, b) do
    k = key(r, g, b)

    case answers do
      %{^k => i} ->
        {i, lut}

      _ ->
        i = closest(p, r, g, b)
        {i, {p, Map.put(answers, k, i)}}
    end
  end

  defp step(v), do: min(31, trunc(v * 31.99))

  defp closest(p, r, g, b) do
    {best, _} =
      Enum.reduce(0..(tuple_size(p) - 1), {0, 1.0e9}, fn i, {best, bd} ->
        {pr, pg, pb} = elem(p, i)
        dr = pr - r
        dg = pg - g
        db = pb - b
        d = 0.3 * dr * dr + 0.5 * dg * dg + 0.2 * db * db
        if d < bd, do: {i, d}, else: {best, bd}
      end)

    best
  end
end
