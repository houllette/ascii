defmodule AsciiArt.Frame do
  @moduledoc """
  One frame of a piece, ready for any renderer.

  `text` is the picture: `rows` lines of `cols` characters joined by `\\n`,
  and `lines` the same split into rows. `colors`, for a coloured piece drawn
  in colour, is a binary of `cols * rows` bytes, one palette index a cell,
  row by row; `palette` holds the `#rrggbb` colours they index and `ground`
  the colour behind them. A palette entry may be `nil`, for cells drawn in
  the renderer's own ink: a piece in one ink with only some of its parts
  coloured (see `AsciiArt.Parts`). A palette is the same for every frame of
  an animation. `cell` is a cell's height in widths (2 for the
  shape of a character, 1 for square).

  Renderers in this library (`AsciiArt.Render.Text`, `AsciiArt.Render.ANSI`,
  the Phoenix components) all take a frame. To draw cells yourself, on a
  framebuffer say, walk `lines` and `colors` together:

      for {line, y} <- Enum.with_index(frame.lines),
          {char, x} <- Enum.with_index(String.graphemes(line)) do
        index = :binary.at(frame.colors, y * frame.cols + x)
        draw(x, y, char, Enum.at(frame.palette, index) || my_ink)
      end
  """

  @type t :: %__MODULE__{
          text: String.t(),
          lines: [String.t()],
          colors: binary() | nil,
          palette: [String.t() | nil] | nil,
          ground: String.t() | nil,
          cols: pos_integer(),
          rows: pos_integer(),
          cell: 1 | 2,
          t: float()
        }

  @enforce_keys [:text, :lines, :cols, :rows, :t]
  defstruct [:text, :lines, :colors, :palette, :ground, :cols, :rows, :t, cell: 2]

  @doc """
  The `#rrggbb` colour of the cell at `x`, `y`, or `nil` without colours or
  in the renderer's own ink.
  """
  @spec color_at(frame :: t(), x :: non_neg_integer(), y :: non_neg_integer()) ::
          String.t() | nil
  def color_at(%__MODULE__{colors: nil}, _x, _y), do: nil

  def color_at(%__MODULE__{colors: colors, palette: palette, cols: cols}, x, y),
    do: Enum.at(palette, :binary.at(colors, y * cols + x))

  @typedoc "A run of cells along row `y` from column `x`: their text and colours."
  @type run :: {y :: non_neg_integer(), x :: non_neg_integer(), String.t(), binary() | nil}

  @doc """
  What changed from `prev` to `frame`, as runs of cells along a row:
  `{y, x, text, colors}`, the colours being the run's palette indices (or
  `nil` without colours). A cell counts as changed if its character or its
  colour did. Changed cells less than `:gap` cells apart (default 4) are
  taken into one run, since each run costs a little to place.

  With no frame before (`nil`), or one of another size or kind, every row is
  a run. Most pieces change a few cells in a hundred a frame, so this is
  what to send to a terminal or a browser that already shows `prev`.
  """
  @spec changes(prev :: t() | nil, frame :: t(), opts :: [gap: pos_integer()]) :: [run()]
  def changes(prev, frame, opts \\ [])

  def changes(
        %__MODULE__{cols: cols, rows: rows} = prev,
        %__MODULE__{cols: cols, rows: rows} = frame,
        opts
      )
      when is_nil(prev.colors) == is_nil(frame.colors) do
    gap = Keyword.get(opts, :gap, 4)

    frame.lines
    |> Enum.zip(prev.lines)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{line, before}, y} ->
      colors = row_colors(frame, y)
      prev_colors = row_colors(prev, y)

      if line == before and colors == prev_colors,
        do: [],
        else: row_changes(y, line, before, colors, prev_colors, gap)
    end)
  end

  def changes(_prev, %__MODULE__{} = frame, _opts) do
    for {line, y} <- Enum.with_index(frame.lines), do: {y, 0, line, row_colors(frame, y)}
  end

  defp row_colors(%__MODULE__{colors: nil}, _y), do: nil

  defp row_colors(%__MODULE__{colors: colors, cols: cols}, y),
    do: binary_part(colors, y * cols, cols)

  defp row_changes(y, line, before, colors, prev_colors, gap) do
    chars = line |> String.codepoints() |> List.to_tuple()
    prev_chars = before |> String.codepoints() |> List.to_tuple()

    0..(tuple_size(chars) - 1)
    |> Enum.filter(fn x ->
      elem(chars, x) != elem(prev_chars, x) or
        (colors != nil and :binary.at(colors, x) != :binary.at(prev_colors, x))
    end)
    |> Enum.reduce([], fn
      x, [{from, to} | spans] when x - to <= gap -> [{from, x} | spans]
      x, spans -> [{x, x} | spans]
    end)
    |> Enum.reverse()
    |> Enum.map(fn {from, to} ->
      text = Enum.map_join(from..to, &elem(chars, &1))
      {y, from, text, colors && binary_part(colors, from, to - from + 1)}
    end)
  end
end
