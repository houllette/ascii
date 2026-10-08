if Code.ensure_loaded?(ExRatatui) do
  defmodule AsciiArt.ExRatatui do
    @moduledoc """
    Frames for [ExRatatui](https://hexdocs.pm/ex_ratatui) terminal UIs: as
    ratatui text, as a `Paragraph`, or placed in an area of the screen.

        def render(state, frame) do
          area = %ExRatatui.Layout.Rect{x: 0, y: 0, width: frame.width, height: frame.height}
          [AsciiArt.ExRatatui.place(state.art, area, title: "donut")]
        end

    A `%AsciiArt.Frame{}` is an `ExRatatui.Widget` too, drawn from the top
    left of its rect with the defaults below, so `[{frame, rect}]` draws it
    as it is.

    For a ready-made app that plays pieces full screen, locally or over SSH,
    see `AsciiArt.ExRatatui.Viewer`; the [ExRatatui guide](ex_ratatui.md)
    has dashboards and testing.

    ## Options

    Every function here takes:

      * `:mode` - how colour is drawn: `:truecolor` (the default), the
        nearest of xterm's 256 colours (`:ansi256`), for terminals without
        24-bit colour, or `:mono`, in the terminal's own colours. As for
        `AsciiArt.Render.ANSI`.
      * `:ground` - paint a coloured piece's ground behind it (default
        `true`).

    and `paragraph/2` and `place/3`:

      * `:title` - a title, on a border around the picture.
      * `:border` - a border without a title (default `false`).

    Only available when `ex_ratatui` is a dependency.
    """

    alias AsciiArt.Frame
    alias AsciiArt.Kit.Palette
    alias AsciiArt.Render.ANSI
    alias ExRatatui.Layout.Rect
    alias ExRatatui.Style
    alias ExRatatui.Text.{Line, Span}
    alias ExRatatui.Widgets.{Block, Paragraph}

    @typedoc "See the module docs."
    @type option ::
            {:mode, ANSI.mode()}
            | {:ground, boolean()}
            | {:title, String.t()}
            | {:border, boolean()}

    @doc """
    The frame as ratatui lines, one a row: a span for each run of one ink,
    on the ground. Spaces show no ink, so they join the run they are in.
    A frame without colours is one plain span a line.
    """
    @spec lines(frame :: Frame.t(), opts :: [option()]) :: [Line.t()]
    def lines(frame, opts \\ [])
    def lines(%Frame{colors: nil, lines: lines}, _opts), do: Enum.map(lines, &plain/1)

    def lines(%Frame{} = frame, opts) do
      case Keyword.get(opts, :mode, :truecolor) do
        :mono -> Enum.map(frame.lines, &plain/1)
        mode -> colored(frame, mode, Keyword.get(opts, :ground, true))
      end
    end

    defp plain(line), do: %Line{spans: [%Span{content: line}]}

    defp colored(%Frame{lines: lines, colors: colors, cols: cols} = frame, mode, ground?) do
      inks = frame.palette |> Enum.map(&%Style{fg: color(&1, mode)}) |> List.to_tuple()

      style =
        if ground? and frame.ground, do: %Style{bg: color(frame.ground, mode)}, else: %Style{}

      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, y} ->
        %Line{spans: runs(line, binary_part(colors, y * cols, cols), inks), style: style}
      end)
    end

    defp color(hex, mode) do
      case {Palette.rgb255(hex), mode} do
        {{r, g, b}, :truecolor} -> {:rgb, r, g, b}
        {rgb, :ansi256} -> {:indexed, ANSI.xterm256(rgb)}
      end
    end

    # Runs of one ink along a line, cut from it: `rest` is what is left of
    # `line`, the run so far starts at byte `start`, and `ink` is its palette
    # index, nil while it has only spaces.
    defp runs(line, colors, inks), do: runs(line, colors, inks, line, 0, nil, [])

    defp runs(<<?\s, rest::binary>>, <<_, colors::binary>>, inks, line, start, ink, acc),
      do: runs(rest, colors, inks, line, start, ink, acc)

    defp runs(<<_::utf8, rest::binary>>, <<i, colors::binary>>, inks, line, start, ink, acc)
         when ink in [nil, i],
         do: runs(rest, colors, inks, line, start, i, acc)

    defp runs(
           <<_::utf8, _::binary>> = rest,
           <<i, _::binary>> = colors,
           inks,
           line,
           start,
           ink,
           acc
         ) do
      at = byte_size(line) - byte_size(rest)
      run = span(binary_part(line, start, at - start), ink, inks)
      runs(rest, colors, inks, line, at, i, [run | acc])
    end

    defp runs(_rest, _colors, inks, line, start, ink, acc) do
      run = span(binary_part(line, start, byte_size(line) - start), ink, inks)
      Enum.reverse([run | acc])
    end

    defp span(run, nil, _inks), do: %Span{content: run}
    defp span(run, ink, inks), do: %Span{content: run, style: elem(inks, ink)}

    @doc """
    The frame as a `Paragraph`, in a bordered `Block` if given a `:title` or
    `border: true`. Its rect wants the frame's `cols` and `rows`, and two
    more of each for a border; `place/3` works that out.
    """
    @spec paragraph(frame :: Frame.t(), opts :: [option()]) :: Paragraph.t()
    def paragraph(%Frame{} = frame, opts \\ []),
      do: %Paragraph{text: lines(frame, opts), block: block(opts)}

    defp block(opts) do
      case Keyword.fetch(opts, :title) do
        {:ok, title} -> %Block{title: title, borders: [:all]}
        :error -> if Keyword.get(opts, :border, false), do: %Block{borders: [:all]}
      end
    end

    @doc """
    The frame as a `Paragraph` and the rect to draw it in: its own size,
    centred in `area`. A box is wide enough for its title, the picture in
    the middle of it. Too big for the area, it fills it and shows its
    middle.
    """
    @spec place(frame :: Frame.t(), area :: Rect.t(), opts :: [option()]) ::
            {Paragraph.t(), Rect.t()}
    def place(%Frame{cols: cols, rows: rows} = frame, %Rect{} = area, opts \\ []) do
      paragraph = paragraph(frame, opts)
      edge = if paragraph.block, do: 2, else: 0
      wide = max(cols, opts |> Keyword.get(:title, "") |> String.length())
      {x, width, left} = fit(area.x, area.width, edge, wide, cols)
      {y, height, top} = fit(area.y, area.height, edge, rows, rows)
      rect = %Rect{x: x, y: y, width: width, height: height}
      alignment = if wide > cols, do: :center, else: :left
      {%{paragraph | scroll: {top, left}, alignment: alignment}, rect}
    end

    # Along one axis, for a picture `size` long wanting `want` and `edge`
    # more: where it starts, how much of the area it takes, and how far into
    # the picture the part shown starts.
    defp fit(start, room, edge, want, _size) when want + edge <= room,
      do: {start + div(room - want - edge, 2), want + edge, 0}

    defp fit(start, room, edge, _want, size),
      do: {start, room, max(div(size - max(room - edge, 0), 2), 0)}
  end

  defimpl ExRatatui.Widget, for: AsciiArt.Frame do
    def render(frame, rect), do: [{AsciiArt.ExRatatui.paragraph(frame), rect}]
  end
end
