defmodule AsciiArt.Kit.Mark do
  @moduledoc """
  What the logos and distros share: three drawings of the same mark.

  `mono` is the mark in one ink, for a `<pre>` or a terminal; `art` the same
  mark drawn for colour; and `ink` gives each cell of `art` its colour, as a
  base-36 digit. A palette holds `n` colours per variant, six variants in
  turn: for a light page as drawn, then lifted once and twice for the
  effect, then the same three for a dark page.

  Each drawing is upstream's raw string without its first character (the
  newline after the opening backtick), as a heredoc, whose own closing
  newline stands for the one before the closing backtick. Lines are padded
  to the frame's width, as upstream pads them.
  """

  alias AsciiArt.Meta

  @type picture :: tuple()

  @doc "A drawing as a tuple of rows, each a tuple of one-character binaries."
  @spec picture(raw :: String.t(), cols :: pos_integer()) :: picture()
  def picture(raw, cols) do
    raw
    |> String.replace_suffix("\n", "")
    |> String.split("\n")
    |> Enum.map(fn line ->
      chars = String.codepoints(line)
      List.to_tuple(chars ++ List.duplicate(" ", max(cols - length(chars), 0)))
    end)
    |> List.to_tuple()
  end

  @doc "The character at `x`, `y`."
  @spec at(pic :: picture(), x :: non_neg_integer(), y :: non_neg_integer()) :: String.t()
  def at(pic, x, y), do: pic |> elem(y) |> elem(x)

  @doc "Colours per variant: a sixth of the palette."
  @spec per_variant(meta :: Meta.t()) :: non_neg_integer()
  def per_variant(%Meta{palette: palette}), do: div(length(palette), 6)

  @doc """
  The palette index of a cell: the variant for the page (light first) and
  the effect's `level` (0 to 2), then the ink digit. A cell whose ink is
  not a digit (JS's `parseInt` gives NaN, which a `Uint8Array` stores as
  0) takes 0.
  """
  @spec index(n :: non_neg_integer(), paper :: boolean(), level :: 0..2, ink :: String.t()) ::
          byte()
  def index(n, paper, level, ink) do
    case Integer.parse(ink, 36) do
      {digit, ""} -> Bitwise.band(if(paper, do: 0, else: 3 * n) + level * n + digit, 0xFF)
      _ -> 0
    end
  end
end
