defmodule Ascii.Compose do
  @moduledoc """
  Frames put together into one: a frame in a bordered panel with a title,
  rules between sections, frames side by side or one above another. For a
  dashboard on a plain terminal (`Ascii.Render.ANSI`), a Nerves device's
  screen, an SVG, or anything else that draws one frame.

      {gauge, _} = Ascii.frame(gauge, t)
      {spark, _} = Ascii.frame(spark, t)

      Ascii.Compose.above([
        Ascii.Compose.beside([
          Ascii.Compose.panel(gauge, title: "load"),
          Ascii.Compose.panel(spark, title: "history", style: :double)
        ]),
        Ascii.Compose.divider(80, label: "processes"),
        Ascii.Compose.text(["pid  name", "123  my_app"])
      ])

  Every function takes and returns `Ascii.Frame`s, so they nest. Each
  frame keeps its colours: the result's palette holds every frame's, once
  each, and cells in no colour (a frame without colours, the spaces between)
  are in the renderer's own ink, a `nil` in the palette. A frame of only
  uncoloured frames has no colours either. A frame's `ground` is kept only
  where every coloured frame shares it; a scene's dark ground is otherwise
  lost, so give one behind the whole with `:ground` (or draw over a dark
  terminal). Composing an animation is composing its frames: draw each
  piece's frame at `t`, then put them together, every tick.
  """

  alias Ascii.{Frame, Ink}
  alias Ascii.Kit.Text

  # Corners top left, top right, bottom left, bottom right; the top and
  # bottom edges; the sides. As box-frames draws them.
  @boxes %{
    single: "┌┐└┘──││",
    double: "╔╗╚╝══║║",
    rounded: "╭╮╰╯──││",
    heavy: "┏┓┗┛━━┃┃",
    dashed: "┌┐└┘┄┄┆┆",
    ascii: "++++--||",
    block: "▛▜▙▟▀▄▌▐"
  }

  @rules %{
    single: "─",
    double: "═",
    heavy: "━",
    dashed: "┄",
    dotted: "· ",
    ascii: "-",
    wave: "_.·°·."
  }

  @typedoc "A colour (as `Ascii.Ink.color/1` takes one), or `nil` for the renderer's own."
  @type color :: String.t() | nil

  @typedoc "Where a smaller frame goes in the room it is given."
  @type align :: :left | :center | :right | :top | :middle | :bottom

  # A picture being put together: rows of {text, colours}, the colours a
  # palette's indices, and that palette (index 0 the renderer's own ink).
  defp cells(%Frame{lines: lines, colors: nil, cols: cols}, map),
    do: {Enum.map(lines, &{&1, :binary.copy(<<0>>, cols)}), map}

  defp cells(%Frame{lines: lines, colors: colors, cols: cols, palette: palette}, map) do
    {at, map} = Enum.map_reduce(palette, map, &index/2)
    at = List.to_tuple(at)

    rows =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, y} ->
        {line, for(<<i <- binary_part(colors, y * cols, cols)>>, into: <<>>, do: <<elem(at, i)>>)}
      end)

    {rows, map}
  end

  # A colour's index in the palette so far, adding it if it is new.
  defp index(nil, map), do: {0, map}

  defp index(color, %{index: index, palette: palette} = map) do
    case index do
      %{^color => i} ->
        {i, map}

      _ ->
        {length(palette),
         %{map | index: Map.put(index, color, length(palette)), palette: palette ++ [color]}}
    end
  end

  defp new_map, do: %{index: %{}, palette: [nil]}

  defp to_frame(rows, map, like, opts) do
    cols = rows |> List.first({"", ""}) |> elem(0) |> Text.length()
    lines = Enum.map(rows, &elem(&1, 0))
    colored? = map.palette != [nil]

    if length(map.palette) > 256,
      do: raise(ArgumentError, "ascii: more than 256 colours in one frame")

    %Frame{
      text: Enum.join(lines, "\n"),
      lines: lines,
      colors: if(colored?, do: IO.iodata_to_binary(Enum.map(rows, &elem(&1, 1)))),
      palette: if(colored?, do: map.palette),
      ground: Keyword.get_lazy(opts, :ground, fn -> ground(like) end),
      cols: cols,
      rows: length(rows),
      cell: like |> Enum.map(& &1.cell) |> Enum.max(fn -> 2 end),
      t: like |> Enum.map(& &1.t) |> Enum.max(fn -> 0.0 end)
    }
  end

  # The ground every coloured frame shares, if they share one.
  defp ground(frames) do
    case frames |> Enum.filter(& &1.colors) |> Enum.map(& &1.ground) |> Enum.uniq() do
      [ground] -> ground
      _ -> nil
    end
  end

  defp blank(cols), do: {String.duplicate(" ", cols), :binary.copy(<<0>>, cols)}

  defp color!(nil), do: nil

  defp color!(color) do
    Ink.color(color) || raise ArgumentError, "ascii: not a colour: #{inspect(color)}"
  end

  @doc """
  Plain text as a frame: lines, each padded to the longest (or `:width`,
  cut to it), in one colour or the renderer's own. For labels, readouts and
  tables beside the pieces.

  ## Options

    * `:width` - the frame's width; lines are cut or padded to it.
    * `:align` - `:left` (the default), `:center` or `:right`.
    * `:color` - the text's colour.
  """
  @spec text(lines :: String.t() | [String.t()], opts :: keyword()) :: Frame.t()
  def text(lines, opts \\ [])
  def text(text, opts) when is_binary(text), do: text(String.split(text, "\n"), opts)

  def text(lines, opts) when is_list(lines) do
    lines = if lines == [], do: [""], else: lines

    width =
      Keyword.get_lazy(opts, :width, fn -> lines |> Enum.map(&Text.length/1) |> Enum.max() end)

    align = Keyword.get(opts, :align, :left)
    {i, map} = index(color!(Keyword.get(opts, :color)), new_map())

    rows =
      for line <- lines do
        line = Text.slice(line, 0, width)
        {align_line(line, width, align), :binary.copy(<<i>>, width)}
      end

    to_frame(rows, map, [], opts)
  end

  defp align_line(line, width, align) do
    room = width - Text.length(line)

    {left, right} =
      case align do
        a when a in [:center, :middle] -> {div(room, 2), room - div(room, 2)}
        a when a in [:right, :bottom] -> {room, 0}
        _left -> {0, room}
      end

    String.duplicate(" ", left) <> line <> String.duplicate(" ", right)
  end

  @doc """
  A rule across `cols` cells, for between sections, with a label in it if
  given.

  ## Options

    * `:style` - `:single` (the default), `:double`, `:heavy`, `:dashed`,
      `:dotted`, `:ascii` or `:wave`.
    * `:label` - text set into the rule, a space either side.
    * `:align` - where the label goes: `:left` (two cells in, the default),
      `:center` or `:right`.
    * `:color`, `:label_color` - the rule's and the label's colours.
  """
  @spec divider(cols :: pos_integer(), opts :: keyword()) :: Frame.t()
  def divider(cols, opts \\ []) when is_integer(cols) and cols > 0 do
    unit = Map.fetch!(@rules, Keyword.get(opts, :style, :single))
    rule = unit |> Text.repeat(ceil(cols / Text.length(unit))) |> Text.slice(0, cols)
    {r, map} = index(color!(Keyword.get(opts, :color)), new_map())
    {l, map} = index(color!(Keyword.get(opts, :label_color)), map)

    {line, colors} =
      case Keyword.get(opts, :label) do
        label when is_binary(label) and label != "" ->
          label = " " <> Text.slice(label, 0, max(cols - 6, 1)) <> " "
          n = Text.length(label)

          at =
            case Keyword.get(opts, :align, :left) do
              :center -> div(cols - n, 2)
              :right -> max(cols - n - 2, 0)
              _left -> min(2, max(cols - n, 0))
            end

          {Text.slice(rule, 0, at) <> label <> Text.slice(rule, at + n),
           :binary.copy(<<r>>, at) <>
             :binary.copy(<<l>>, n) <>
             :binary.copy(<<r>>, max(cols - at - n, 0))}

        _none ->
          {rule, :binary.copy(<<r>>, cols)}
      end

    to_frame([{Text.slice(line, 0, cols), binary_part(colors, 0, cols)}], map, [], opts)
  end

  @doc """
  The frame in a box, a title set into its top edge.

  ## Options

    * `:title` - text in the top edge, a space either side.
    * `:style` - the box: `:rounded` (the default), `:single`, `:double`,
      `:heavy`, `:dashed`, `:ascii` or `:block`.
    * `:padding` - blank cells between the box and the frame, at the sides
      (default 1); `:padding_y` above and below (default 0).
    * `:width`, `:height` - the panel's whole size, box included, the frame
      placed in it by `:align`: for panels of one size in a row or a grid.
      The panel is never smaller than the frame and its title need, so a
      frame too big for the room keeps all of its picture.
    * `:align` - where the frame sits in a larger panel: `:center` (the
      default), `:left` or `:right`; and `:valign`, `:middle` (the
      default), `:top` or `:bottom`.
    * `:color`, `:title_color` - the box's and the title's colours.
    * `:ground` - the result's ground.
  """
  @spec panel(frame :: Frame.t(), opts :: keyword()) :: Frame.t()
  def panel(%Frame{} = frame, opts \\ []) do
    box = @boxes |> Map.fetch!(Keyword.get(opts, :style, :rounded)) |> String.codepoints()
    [tl, tr, bl, br, top, bottom, left, right] = box
    px = Keyword.get(opts, :padding, 1)
    py = Keyword.get(opts, :padding_y, 0)
    title = Keyword.get(opts, :title)
    title = if title in [nil, ""], do: nil, else: " " <> title <> " "
    title_n = if title, do: Text.length(title), else: 0

    inner_w = max(Keyword.get(opts, :width, 0) - 2, max(frame.cols + 2 * px, title_n + 2))
    inner_h = max(Keyword.get(opts, :height, 0) - 2, frame.rows + 2 * py)

    {inside, map} = cells(frame, new_map())
    {b, map} = index(color!(Keyword.get(opts, :color)), map)
    {t, map} = index(color!(Keyword.get(opts, :title_color)), map)

    # The frame placed in the room inside the padding, then the padding.
    inside =
      inside
      |> place(
        {frame.cols, frame.rows},
        {inner_w - 2 * px, inner_h - 2 * py},
        {Keyword.get(opts, :align, :center), Keyword.get(opts, :valign, :middle)}
      )
      |> place({inner_w - 2 * px, inner_h - 2 * py}, {inner_w, inner_h}, {:center, :middle})

    edge = fn corner_l, fill, corner_r ->
      {corner_l <> String.duplicate(fill, inner_w) <> corner_r, :binary.copy(<<b>>, inner_w + 2)}
    end

    {top_line, top_colors} = edge.(tl, top, tr)

    top_row =
      if title do
        n = min(title_n, inner_w - 1)

        line =
          Text.slice(top_line, 0, 2) <> Text.slice(title, 0, n) <> Text.slice(top_line, 2 + n)

        colors = <<b, b>> <> :binary.copy(<<t>>, n) <> binary_part(top_colors, 2 + n, inner_w - n)
        {line, colors}
      else
        {top_line, top_colors}
      end

    sides = for {line, colors} <- inside, do: {left <> line <> right, <<b>> <> colors <> <<b>>}
    to_frame([top_row | sides] ++ [edge.(bl, bottom, br)], map, [frame], opts)
  end

  # Rows `size` big set in `room`, as `align` says, padded with blank cells.
  defp place(rows, {cols, n}, {w, h}, {halign, valign}) do
    {left, _right} = split(w - cols, halign)
    {above, below} = split(h - n, valign)

    pad = fn {line, colors} ->
      {String.duplicate(" ", left) <> line <> String.duplicate(" ", w - cols - left),
       :binary.copy(<<0>>, left) <> colors <> :binary.copy(<<0>>, w - cols - left)}
    end

    List.duplicate(blank(w), above) ++ Enum.map(rows, pad) ++ List.duplicate(blank(w), below)
  end

  defp split(room, align) when align in [:center, :middle],
    do: {div(room, 2), room - div(room, 2)}

  defp split(room, align) when align in [:right, :bottom], do: {room, 0}
  defp split(room, _align), do: {0, room}

  @doc """
  Frames side by side, their tops level (or as `:align` says), `:gap`
  blank cells apart (default 1).

  ## Options

    * `:gap` - blank cells between neighbours (default 1).
    * `:align` - `:top` (the default), `:middle` or `:bottom`.
    * `:ground` - the result's ground.
  """
  @spec beside(frames :: [Frame.t(), ...], opts :: keyword()) :: Frame.t()
  def beside([_ | _] = frames, opts \\ []) do
    gap = Keyword.get(opts, :gap, 1)
    align = Keyword.get(opts, :align, :top)
    h = frames |> Enum.map(& &1.rows) |> Enum.max()

    {columns, map} =
      Enum.map_reduce(frames, new_map(), fn frame, map ->
        {rows, map} = cells(frame, map)
        {place(rows, {frame.cols, frame.rows}, {frame.cols, h}, {:left, align}), map}
      end)

    spacer = List.duplicate(blank(gap), h)

    rows =
      columns
      |> Enum.intersperse(spacer)
      |> Enum.zip_with(fn cells ->
        {Enum.map_join(cells, &elem(&1, 0)),
         cells |> Enum.map(&elem(&1, 1)) |> IO.iodata_to_binary()}
      end)

    to_frame(rows, map, frames, opts)
  end

  @doc """
  Frames one above another, their left edges level (or as `:align` says),
  `:gap` blank rows apart (default 0).

  ## Options

    * `:gap` - blank rows between neighbours (default 0).
    * `:align` - `:left` (the default), `:center` or `:right`.
    * `:ground` - the result's ground.
  """
  @spec above(frames :: [Frame.t(), ...], opts :: keyword()) :: Frame.t()
  def above([_ | _] = frames, opts \\ []) do
    gap = Keyword.get(opts, :gap, 0)
    align = Keyword.get(opts, :align, :left)
    w = frames |> Enum.map(& &1.cols) |> Enum.max()

    {blocks, map} =
      Enum.map_reduce(frames, new_map(), fn frame, map ->
        {rows, map} = cells(frame, map)
        {place(rows, {frame.cols, frame.rows}, {w, frame.rows}, {align, :top}), map}
      end)

    rows = blocks |> Enum.intersperse(List.duplicate(blank(w), gap)) |> Enum.concat()
    to_frame(rows, map, frames, opts)
  end

  @doc """
  The frame in exactly `cols` by `rows` cells: placed as `:align` and
  `:valign` say in a larger room, or its middle (as aligned) in a smaller.
  For a frame to fill an area of a screen.

  ## Options

    * `:align` - `:center` (the default), `:left` or `:right`.
    * `:valign` - `:middle` (the default), `:top` or `:bottom`.
  """
  @spec fit(frame :: Frame.t(), cols :: pos_integer(), rows :: pos_integer(), opts :: keyword()) ::
          Frame.t()
  def fit(%Frame{} = frame, cols, rows, opts \\ []) do
    halign = Keyword.get(opts, :align, :center)
    valign = Keyword.get(opts, :valign, :middle)
    {inside, map} = cells(frame, new_map())

    {left, _} = split(frame.cols - cols, halign)
    {top, _} = split(frame.rows - rows, valign)

    cut =
      if frame.cols > cols or frame.rows > rows do
        inside
        |> Enum.drop(max(top, 0))
        |> Enum.take(rows)
        |> Enum.map(fn {line, colors} ->
          from = max(left, 0)
          n = min(cols, frame.cols)
          {Text.slice(line, from, from + n), binary_part(colors, from, n)}
        end)
      else
        inside
      end

    size = {min(cols, frame.cols), min(rows, frame.rows)}
    to_frame(place(cut, size, {cols, rows}, {halign, valign}), map, [frame], opts)
  end
end
