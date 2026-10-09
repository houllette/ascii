defmodule AsciiArt.Ink do
  @moduledoc """
  Colour for a piece drawn in one ink: one colour for every character, or
  several as a gradient across the picture, and colours for its parts.

  Most pieces are text in one ink, the page's or the terminal's own. Given
  an ink (`AsciiArt.new(piece, ink: ...)`), their frames come with colours,
  so every renderer draws them as it draws a coloured piece: a canvas in the
  browser, 24-bit or xterm-256 escapes in a terminal, and plain text where
  colour cannot be shown (`mode: :mono`). The picture itself is unchanged,
  character for character: the ink is laid over it, never drawn by the piece.

  A coloured piece keeps its own palette; drawn in one ink (`color: false`)
  it takes the ink like any other.

      {:ok, anim} = AsciiArt.new("big-text", ink: ["#ff5f6d", "#ffc371"])
      {:ok, anim} = AsciiArt.new("donut", ink: "#7fdbca")
      {:ok, anim} = AsciiArt.new("wave-text", ink: "#36d1dc,#5b86e5", gradient: :vertical)

  Pieces that know their parts (a file tree's folders, a boot log's
  statuses) take colours for those too, with `:parts`, over the ink or
  without one: see `AsciiArt.Parts`.

  ## Colours

  `#rrggbb` or `#rgb`, the `#` optional; several as a list or as one string,
  comma-separated (as from a form or a command line), up to #{16}. One colour
  is every character's. Several run evenly from the first to the last across
  the whole picture, in a straight line between each and the next, as CSS's
  `linear-gradient` does, so a piece whose text moves (a marquee, a wave)
  moves through them.

  ## CSS variables

  One ink, or a part's colour, can be a CSS custom property, so a piece on
  a page takes the page's own colours, and follows them into dark mode:
  `"var(--color-success)"`, or with a colour for where there is no CSS,
  `"var(--color-success, #3fb950)"`. In HTML (`AsciiArt.Render.HTML`, the
  Phoenix players, `AsciiArt.Render.SVG`) the variable is the colour; a
  terminal draws the fallback, or its own ink without one (`resolve/1`).
  Several inks run as a gradient, worked out here, so they must be colours.

  ## Gradients

    * `:horizontal` (the default) - left to right.
    * `:vertical` - top to bottom.
    * `:diagonal` - top left to bottom right, at 45° on screen, cells being
      as tall as the piece's `cell` says.

  A gradient is #{65} steps, whatever the picture's size, so its palette is
  the same for every frame (a player sends it once) and a wide picture costs
  few escapes in a terminal and few spans in HTML.
  """

  alias AsciiArt.{Frame, Parts}
  alias AsciiArt.Kit.Palette

  @max_colors 16
  @steps 65
  @gradients [:horizontal, :vertical, :diagonal]

  @typedoc "Which way several colours run."
  @type gradient :: :horizontal | :vertical | :diagonal

  @typedoc """
  An ink: its colours, as `#rrggbb` or a CSS variable (`nil` for the
  renderer's own), which way they run, and colours for parts (see `AsciiArt.Parts`). Made by
  `cast/2` and `put_parts/2`; the rest is its layout for one size of frame,
  filled in as it is needed.
  """
  @type t :: %__MODULE__{
          colors: [String.t(), ...] | nil,
          gradient: gradient(),
          parts: Parts.colors(),
          size: {pos_integer(), pos_integer(), 1 | 2} | nil,
          palette: [String.t() | nil] | nil,
          cells: binary() | nil,
          index: %{optional(String.t()) => non_neg_integer() | :base} | nil
        }

  @enforce_keys [:colors]
  defstruct [
    :colors,
    gradient: :horizontal,
    parts: %{},
    size: nil,
    palette: nil,
    cells: nil,
    index: nil
  ]

  @doc """
  An ink from outside (code, LiveView params, a command line): its colours
  and, for several, which way they run. No colours at all (`nil`, `""` or
  `[]`) is no ink. Never creates an atom.

      iex> AsciiArt.Ink.cast("#F80")
      {:ok, %AsciiArt.Ink{colors: ["#ff8800"], gradient: :horizontal}}

      iex> AsciiArt.Ink.cast("#ff5f6d,#ffc371", "vertical")
      {:ok, %AsciiArt.Ink{colors: ["#ff5f6d", "#ffc371"], gradient: :vertical}}

      iex> AsciiArt.Ink.cast("red")
      {:error, {:invalid_option, :ink}}
  """
  @spec cast(colors :: term(), gradient :: term()) ::
          {:ok, t() | nil} | AsciiArt.Options.error()
  def cast(colors, gradient \\ nil) do
    with {:ok, gradient} <- gradient(gradient),
         {:ok, colors} <- colors(colors) do
      {:ok, colors && %__MODULE__{colors: colors, gradient: gradient}}
    end
  end

  defp gradient(nil), do: {:ok, :horizontal}
  defp gradient(""), do: {:ok, :horizontal}
  defp gradient(gradient) when gradient in @gradients, do: {:ok, gradient}

  defp gradient(name) when is_binary(name) do
    case Enum.find(@gradients, &(Atom.to_string(&1) == name)) do
      nil -> {:error, {:invalid_option, :gradient}}
      gradient -> {:ok, gradient}
    end
  end

  defp gradient(_gradient), do: {:error, {:invalid_option, :gradient}}

  defp colors(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:ok, nil}
      # A variable's fallback follows a comma of its own.
      "var(" <> _ = var -> colors([var])
      text -> text |> String.split(",") |> Enum.map(&String.trim/1) |> colors()
    end
  end

  defp colors(nil), do: {:ok, nil}
  defp colors([]), do: {:ok, nil}

  # One ink may be a CSS variable; a gradient's are mixed here, so colours.
  defp colors([one]) do
    case color(one) do
      nil -> {:error, {:invalid_option, :ink}}
      color -> {:ok, [color]}
    end
  end

  defp colors(list) when is_list(list) and length(list) <= @max_colors do
    hexes = Enum.map(list, &hex/1)
    if Enum.all?(hexes), do: {:ok, hexes}, else: {:error, {:invalid_option, :ink}}
  end

  defp colors(_colors), do: {:error, {:invalid_option, :ink}}

  @doc false
  # A colour as `#rrggbb`, from `#rrggbb` or `#rgb`, the `#` optional; nil
  # if it is not one.
  @spec hex(color :: term()) :: String.t() | nil
  def hex("#" <> digits), do: digits(digits)
  def hex(digits) when is_binary(digits), do: digits(digits)
  def hex(_other), do: nil

  @css_var ~r/^var\(\s*(--[A-Za-z0-9_-]+)\s*(?:,\s*(#?[0-9A-Fa-f]{3}|#?[0-9A-Fa-f]{6})\s*)?\)$/

  @doc """
  A colour from outside, as this library keeps it: `#rrggbb` (from
  `#rrggbb` or `#rgb`, the `#` optional), or a CSS variable as
  `var(--name)` or `var(--name, #rrggbb)`; `nil` if it is neither.

      iex> AsciiArt.Ink.color("F80")
      "#ff8800"
      iex> AsciiArt.Ink.color("var( --accent ,#FFF)")
      "var(--accent, #ffffff)"
      iex> AsciiArt.Ink.color("var(--x);color:red")
      nil
  """
  @spec color(color :: term()) :: String.t() | nil
  def color(color) when is_binary(color) do
    color = String.trim(color)

    case Regex.run(@css_var, color, capture: :all_but_first) do
      [name] -> "var(#{name})"
      [name, fallback] -> "var(#{name}, #{hex(fallback)})"
      nil -> hex(color)
    end
  end

  def color(_other), do: nil

  @doc """
  The `#rrggbb` to draw a colour in where CSS cannot be read (a terminal, a
  framebuffer): the colour itself, a CSS variable's fallback, or `nil` for
  the renderer's own ink.

      iex> AsciiArt.Ink.resolve("var(--ok, #3fb950)")
      "#3fb950"
      iex> AsciiArt.Ink.resolve("var(--ok)")
      nil
  """
  @spec resolve(color :: String.t() | nil) :: String.t() | nil
  def resolve(nil), do: nil
  def resolve("#" <> _ = hex), do: hex

  def resolve("var(" <> _ = var) do
    case Regex.run(@css_var, var, capture: :all_but_first) do
      [_name, fallback] -> hex(fallback)
      _ -> nil
    end
  end

  defp digits(<<r, g, b>>), do: digits(<<r, r, g, g, b, b>>)

  defp digits(<<_::binary-size(6)>> = digits) do
    case Base.decode16(digits, case: :mixed) do
      {:ok, _} -> "#" <> String.downcase(digits)
      :error -> nil
    end
  end

  defp digits(_digits), do: nil

  @doc """
  The ink with colours for parts (as `AsciiArt.Parts.cast/2` makes them),
  laid over its own. Without an ink, the parts take theirs over the
  renderer's own ink; without parts, the ink is as it was.
  """
  @spec put_parts(ink :: t() | nil, parts :: Parts.colors()) :: t() | nil
  def put_parts(ink, parts) when map_size(parts) == 0, do: ink
  def put_parts(nil, parts), do: %__MODULE__{colors: nil, parts: parts}
  def put_parts(%__MODULE__{} = ink, parts), do: %{ink | parts: parts, size: nil}

  @doc false
  @spec parts?(ink :: t() | nil) :: boolean()
  def parts?(%__MODULE__{parts: parts}), do: map_size(parts) > 0
  def parts?(nil), do: false

  @doc """
  The frame in this ink: its text as it is, each cell given a colour, and no
  ground behind it. With `parts`, the frame's runs of parts (see
  `AsciiArt.Parts`), a part with a colour of its own takes it. A frame with
  colours of its own, or no ink (`nil`), is left as it is.
  """
  @spec tint(frame :: Frame.t(), ink :: t() | nil, parts :: Parts.t() | nil) :: Frame.t()
  def tint(frame, ink, parts \\ nil)

  def tint(
        %Frame{colors: nil, cols: cols, rows: rows, cell: cell} = frame,
        %__MODULE__{} = ink,
        parts
      ) do
    ink = fit(ink, cols, rows, cell)
    cells = if parts && ink.index != %{}, do: paint(ink, parts), else: ink.cells
    %{frame | colors: cells, palette: ink.palette, ground: nil}
  end

  def tint(%Frame{} = frame, _ink, _parts), do: frame

  @doc false
  # The ink laid out for frames of this size, once: an animation keeps it,
  # so each frame takes it as it is.
  @spec fit(ink :: t() | nil, cols :: pos_integer(), rows :: pos_integer(), cell :: 1 | 2) ::
          t() | nil
  def fit(nil, _cols, _rows, _cell), do: nil
  def fit(%__MODULE__{size: {cols, rows, cell}} = ink, cols, rows, cell), do: ink

  def fit(%__MODULE__{} = ink, cols, rows, cell) do
    {base, cells} = layout(ink, cols, rows, cell)
    {palette, index} = part_palette(base, ink.parts)
    %{ink | size: {cols, rows, cell}, palette: palette, cells: cells, index: index}
  end

  # The parts' colours after the base's, each once; and each part's index,
  # or :base for a part given nil.
  defp part_palette(base, parts) do
    colors = parts |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
    at = colors |> Enum.with_index(length(base)) |> Map.new()
    {base ++ colors, Map.new(parts, fn {name, color} -> {name, Map.get(at, color, :base)} end)}
  end

  defp layout(%{colors: nil}, cols, rows, _cell), do: {[nil], :binary.copy(<<0>>, cols * rows)}
  defp layout(%{colors: [one]}, cols, rows, _cell), do: {[one], :binary.copy(<<0>>, cols * rows)}

  defp layout(%{colors: colors, gradient: :horizontal}, cols, rows, _cell) do
    step = step(cols - 1)
    row = for x <- 0..(cols - 1), into: <<>>, do: <<step.(x)>>
    {steps(colors), :binary.copy(row, rows)}
  end

  defp layout(%{colors: colors, gradient: :vertical}, cols, rows, _cell) do
    step = step(rows - 1)
    {steps(colors), for(y <- 0..(rows - 1), into: <<>>, do: :binary.copy(<<step.(y)>>, cols))}
  end

  # A cell `cell` widths tall is `cell` steps along the diagonal for every
  # one across, so the colours run at 45° as the picture is shown.
  defp layout(%{colors: colors, gradient: :diagonal}, cols, rows, cell) do
    step = step(cols - 1 + cell * (rows - 1))

    {steps(colors),
     for(y <- 0..(rows - 1), x <- 0..(cols - 1), into: <<>>, do: <<step.(x + cell * y)>>)}
  end

  # The gradient's @steps colours, evenly from the first to the last.
  defp steps(colors), do: for(i <- 0..(@steps - 1), do: at(colors, i / (@steps - 1)))

  # The step nearest each place from 0 to `last` along the gradient.
  defp step(0), do: fn _place -> 0 end
  defp step(last), do: fn place -> round(place / last * (@steps - 1)) end

  # The colour a fraction `f` of the way along, between the two colours it
  # falls between.
  defp at(colors, f) do
    segments = length(colors) - 1
    i = min(trunc(f * segments), segments - 1)
    t = f * segments - i
    {r0, g0, b0} = colors |> Enum.at(i) |> Palette.rgb255()
    {r1, g1, b1} = colors |> Enum.at(i + 1) |> Palette.rgb255()
    "#" <> Base.encode16(<<mix(r0, r1, t), mix(g0, g1, t), mix(b0, b1, t)>>, case: :lower)
  end

  defp mix(a, b, t), do: round(a + (b - a) * t)

  # The base's cells, with each run of a part that has a colour in it. A row
  # whose runs do not make it up exactly keeps the base.
  defp paint(%__MODULE__{cells: base, index: index, size: {cols, rows, _}}, parts) do
    (parts ++ List.duplicate([], rows))
    |> Enum.take(rows)
    |> Enum.with_index()
    |> Enum.map(fn {runs, y} -> row(runs, binary_part(base, y * cols, cols), index, cols) end)
    |> IO.iodata_to_binary()
  end

  defp row(runs, base, index, cols) do
    {cells, x} =
      Enum.reduce(runs, {[], 0}, fn {name, text}, {cells, x} ->
        n = count(text)

        cell =
          case x + n <= cols and color_of(index, name) do
            false -> ""
            i when is_integer(i) -> :binary.copy(<<i>>, n)
            _base -> binary_part(base, x, n)
          end

        {[cells, cell], x + n}
      end)

    if x == cols, do: cells, else: base
  end

  defp count(text), do: for(<<_::utf8 <- text>>, reduce: 0, do: (n -> n + 1))

  # A part's palette index: its own, or its parent's, or nil for the base.
  defp color_of(_index, nil), do: nil

  defp color_of(index, name) do
    case index do
      %{^name => i} -> i
      _ -> if parent = Parts.parent(name), do: color_of(index, parent)
    end
  end
end
