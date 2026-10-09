if Code.ensure_loaded?(ExRatatui) do
  defmodule Ascii.ExRatatui do
    @moduledoc """
    Frames for [ExRatatui](https://hexdocs.pm/ex_ratatui) terminal UIs: as
    ratatui text, as a `Paragraph`, or placed in an area of the screen.

        def render(state, frame) do
          area = %ExRatatui.Layout.Rect{x: 0, y: 0, width: frame.width, height: frame.height}
          [Ascii.ExRatatui.place(state.art, area, title: "donut")]
        end

    A `%Ascii.Frame{}` is an `ExRatatui.Widget` too, drawn from the top
    left of its rect with the defaults below, so `[{frame, rect}]` draws it
    as it is.

    For a ready-made app that plays pieces full screen, locally or over SSH,
    see `Ascii.ExRatatui.Viewer`; the [ExRatatui guide](ex_ratatui.md)
    has dashboards and testing.

    ## Options

    Every function here takes:

      * `:mode` - how colour is drawn: `:truecolor` (the default), the
        nearest of xterm's 256 colours (`:ansi256`), for terminals without
        24-bit colour, or `:mono`, in the terminal's own colours. As for
        `Ascii.Render.ANSI`.
      * `:ground` - paint a coloured piece's ground behind it (default
        `true`).

    and `paragraph/2` and `place/3`:

      * `:title` - a title, on a border around the picture.
      * `:border` - a border without a title (default `false`).

    Only available when `ex_ratatui` is a dependency.
    """

    alias Ascii.{Frame, Ink}
    alias Ascii.Kit.Palette
    alias Ascii.Render.ANSI
    alias ExRatatui.Event.{Key, Mouse}
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

    # The terminal's own for nil, a cell in no coloured part, and for a CSS
    # variable without a fallback.
    defp color(color, mode) do
      case Ink.resolve(color) do
        nil -> nil
        hex -> rgb(Palette.rgb255(hex), mode)
      end
    end

    defp rgb({r, g, b}, :truecolor), do: {:rgb, r, g, b}
    defp rgb(rgb, :ansi256), do: {:indexed, ANSI.xterm256(rgb)}

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

    @doc """
    An ExRatatui event as one for a piece (`t:Ascii.event/0`), or `nil`:

      * a key pressed or held, by its code (`"up"`, `"enter"`, `"a"`), unless
        ctrl, alt or super is held with it;
      * a left click inside the picture, as the frame's cell clicked.
        `placed` says where the picture is: what `place/3` returned (its
        border, centring and scroll allowed for), or the rect whose top
        left cell is the frame's (as `[{frame, rect}]` draws it).

    Mouse events need `mouse_capture: true` (see `ExRatatui.run/2`).
    """
    @spec event(
            event :: ExRatatui.Event.Key.t() | ExRatatui.Event.Mouse.t() | term(),
            placed :: {Paragraph.t(), Rect.t()} | Rect.t()
          ) :: Ascii.event() | nil
    def event(event, placed)

    def event(%Key{code: code, kind: kind, modifiers: mods}, _placed)
        when kind in ["press", "repeat"] and is_binary(code) and code != "" do
      if Enum.any?(mods, &(&1 in ["ctrl", "alt", "super", "hyper", "meta"])),
        do: nil,
        else: {:key, code}
    end

    def event(%Mouse{kind: "down", button: "left", x: x, y: y}, placed) do
      {x0, y0, cols, rows, %Rect{} = shown} = origin(placed)
      {cx, cy} = {x - x0, y - y0}

      if x >= shown.x and y >= shown.y and x < shown.x + shown.width and
           y < shown.y + shown.height and cx >= 0 and cy >= 0 and cx < cols and cy < rows,
         do: {:click, cx, cy}
    end

    def event(_event, _placed), do: nil

    # Where the frame's top left cell is on screen, its size, and the rect
    # it shows in.
    defp origin(%Rect{x: x, y: y, width: w, height: h} = rect), do: {x, y, w, h, rect}

    defp origin({%Paragraph{} = paragraph, %Rect{} = rect}) do
      edge = if paragraph.block, do: 1, else: 0
      {top, left} = paragraph.scroll || {0, 0}

      inner = %Rect{
        x: rect.x + edge,
        y: rect.y + edge,
        width: max(rect.width - 2 * edge, 0),
        height: max(rect.height - 2 * edge, 0)
      }

      cols = paragraph.text |> List.first(%Line{spans: []}) |> width()

      # A box wider than the picture, for its title, centres it.
      shift = if paragraph.alignment == :center, do: max(div(inner.width - cols, 2), 0), else: 0
      {inner.x + shift - left, inner.y - top, cols, length(paragraph.text), inner}
    end

    defp width(%Line{spans: spans}),
      do: spans |> Enum.map(&String.length(&1.content)) |> Enum.sum()

    @doc """
    An ExRatatui event for a playing piece (see `event/2`), taken up as
    `Ascii.handle_event/2` takes it: `{:ok, anim}`, or `:ignore` for an
    event that is not one for a piece, or that it had no use for.

        def handle_event(event, state) do
          case Ascii.ExRatatui.handle_event(state.tree, event, state.placed) do
            {:ok, tree} -> {:noreply, %{state | tree: tree}}
            :ignore -> {:noreply, state}
          end
        end
    """
    @spec handle_event(
            anim :: Ascii.Animation.t(),
            event :: term(),
            placed :: {Paragraph.t(), Rect.t()} | Rect.t()
          ) :: {:ok, Ascii.Animation.t()} | :ignore
    def handle_event(anim, event, placed) do
      case event(event, placed) do
        nil -> :ignore
        event -> Ascii.handle_event(anim, event)
      end
    end
  end

  defimpl ExRatatui.Widget, for: Ascii.Frame do
    def render(frame, rect), do: [{Ascii.ExRatatui.paragraph(frame), rect}]
  end
end
