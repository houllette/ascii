defmodule AsciiArt.Render.ANSI do
  @moduledoc """
  A frame for a terminal: text with ANSI colour escapes.

  Coloured frames take each cell's palette colour, as 24-bit colour
  (`:truecolor`, the default), the nearest of xterm's 256 (`:ansi256`), or
  none at all (`:mono`). Escapes are emitted once a run of one colour, and
  spaces never start a run, so a frame costs little more than its text. A
  piece with a `ground` gets it as the background, unless `ground: false`.
  Each line ends by resetting the colours, so nothing bleeds past the
  picture.

  Frames without colours (text pieces, or `color: false`) are plain text in
  every mode, in the terminal's own colours. A `nil` in a palette (cells in
  no coloured part of a piece, see `AsciiArt.Parts`) is the terminal's own
  foreground too, and a CSS variable (see `AsciiArt.Ink`) is its fallback
  colour, or the terminal's own without one.

  To animate in place, move the cursor home before each frame:

      IO.write([ANSI.hide_cursor(), ANSI.clear()])
      IO.write([ANSI.home(), ANSI.render(frame)])
      # ...
      IO.write([ANSI.reset(), ANSI.show_cursor()])

  `AsciiArt.Player` and `mix ascii_art.play` do this for you.
  """

  alias AsciiArt.{Frame, Ink}
  alias AsciiArt.Kit.Palette

  @type mode :: :truecolor | :ansi256 | :mono

  @doc """
  The frame as iodata.

  ## Options

    * `:mode` - `:truecolor` (default), `:ansi256` or `:mono`.
    * `:ground` - paint the piece's ground behind it (default `true`).
  """
  @spec render(frame :: Frame.t(), opts :: [mode: mode(), ground: boolean()]) :: iodata()
  def render(frame, opts \\ [])
  def render(%Frame{colors: nil, text: text}, _opts), do: text

  def render(%Frame{} = frame, opts) do
    case Keyword.get(opts, :mode, :truecolor) do
      :mono -> frame.text
      mode -> colored(frame, mode, Keyword.get(opts, :ground, true))
    end
  end

  defp colored(
         %Frame{lines: lines, colors: colors, cols: cols, palette: palette} = frame,
         mode,
         ground?
       ) do
    inks = inks(palette, mode)
    bg = if ground? and frame.ground, do: sgr(mode, 48, Palette.rgb255(frame.ground)), else: []

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, y} ->
      indices = :binary.bin_to_list(colors, y * cols, cols)
      [bg, runs(String.codepoints(line), indices, inks, nil, []), reset()]
    end)
    |> Enum.intersperse(?\n)
  end

  @doc """
  What changed from `prev` to `frame`, as iodata that moves the cursor to
  each run of cells that changed and writes it (see
  `AsciiArt.Frame.changes/3`); nothing at all when the picture did not
  change. With `prev` `nil`, the whole frame, each row placed.

  A terminal that already shows `prev` needs only this, which for most
  pieces is a few cells in a hundred: over SSH or a serial console, far less
  to send than `render/2` every frame.

  ## Options

    * `:mode`, `:ground` - as for `render/2`.
    * `:at` - `{row, column}` of the screen where the frame's top left cell
      is, counting from 1 (default `{1, 1}`).
  """
  @spec changes(
          prev :: Frame.t() | nil,
          frame :: Frame.t(),
          opts :: [mode: mode(), ground: boolean(), at: {pos_integer(), pos_integer()}]
        ) :: iodata()
  def changes(prev, %Frame{} = frame, opts \\ []) do
    {row, col} = Keyword.get(opts, :at, {1, 1})
    paint = painter(frame, Keyword.get(opts, :mode, :truecolor), Keyword.get(opts, :ground, true))

    for {y, x, text, colors} <- Frame.changes(prev, frame),
        do: [move(row + y, col + x), paint.(text, colors)]
  end

  defp painter(%Frame{colors: nil}, _mode, _ground?), do: fn text, _colors -> text end
  defp painter(_frame, :mono, _ground?), do: fn text, _colors -> text end

  defp painter(%Frame{palette: palette} = frame, mode, ground?) do
    inks = inks(palette, mode)
    bg = if ground? and frame.ground, do: sgr(mode, 48, Palette.rgb255(frame.ground)), else: []

    fn text, colors ->
      [bg, runs(String.codepoints(text), :binary.bin_to_list(colors), inks, nil, []), reset()]
    end
  end

  defp runs([], _indices, _inks, _current, acc), do: Enum.reverse(acc)

  defp runs([" " | chars], [_ | indices], inks, current, acc),
    do: runs(chars, indices, inks, current, [" " | acc])

  defp runs([ch | chars], [i | indices], inks, i, acc),
    do: runs(chars, indices, inks, i, [ch | acc])

  defp runs([ch | chars], [i | indices], inks, _current, acc),
    do: runs(chars, indices, inks, i, [ch, elem(inks, i) | acc])

  defp inks(palette, mode), do: palette |> Enum.map(&ink(mode, &1)) |> List.to_tuple()

  # The terminal's own foreground for nil, and for a CSS variable without a
  # fallback.
  defp ink(mode, color) do
    case Ink.resolve(color) do
      nil -> "\e[39m"
      hex -> sgr(mode, 38, Palette.rgb255(hex))
    end
  end

  defp sgr(:truecolor, layer, {r, g, b}), do: "\e[#{layer};2;#{r};#{g};#{b}m"
  defp sgr(:ansi256, layer, rgb), do: "\e[#{layer};5;#{xterm256(rgb)}m"

  @cube [0, 95, 135, 175, 215, 255]

  @doc "The xterm-256 colour nearest an RGB colour: a step of the 6×6×6 cube or of the grey ramp."
  @spec xterm256({byte(), byte(), byte()}) :: 16..255
  def xterm256({r, g, b}) do
    [cr, cg, cb] = Enum.map([r, g, b], &cube_step/1)
    cube = {Enum.at(@cube, cr), Enum.at(@cube, cg), Enum.at(@cube, cb)}
    grey = min(23, max(0, div(div(r + g + b, 3) - 3, 10)))
    level = 8 + 10 * grey

    if distance({r, g, b}, cube) <= distance({r, g, b}, {level, level, level}),
      do: 16 + 36 * cr + 6 * cg + cb,
      else: 232 + grey
  end

  defp cube_step(v) when v < 48, do: 0
  defp cube_step(v) when v < 115, do: 1
  defp cube_step(v), do: div(v - 35, 40)

  defp distance({a, b, c}, {x, y, z}),
    do: (a - x) * (a - x) + (b - y) * (b - y) + (c - z) * (c - z)

  @doc "Moves the cursor to the top left."
  @spec home() :: String.t()
  def home, do: "\e[H"

  @doc "Moves the cursor to `row`, `column`, counting from 1."
  @spec move(row :: pos_integer(), column :: pos_integer()) :: String.t()
  def move(row, column), do: "\e[#{row};#{column}H"

  @doc "Clears the screen."
  @spec clear() :: String.t()
  def clear, do: "\e[2J"

  @doc "Hides the cursor."
  @spec hide_cursor() :: String.t()
  def hide_cursor, do: "\e[?25l"

  @doc "Shows the cursor."
  @spec show_cursor() :: String.t()
  def show_cursor, do: "\e[?25h"

  @doc "Resets colours."
  @spec reset() :: String.t()
  def reset, do: "\e[0m"
end
