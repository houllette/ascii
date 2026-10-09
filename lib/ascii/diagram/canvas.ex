defmodule Ascii.Diagram.Canvas do
  @moduledoc false

  alias Ascii.{Compose, Frame, Ink}
  alias Ascii.Diagram.{Style, Text}
  alias Ascii.Kit.Grid

  @spec frame(layout :: Ascii.Diagram.Layout.t(), opts :: keyword()) ::
          {:ok, Frame.t()} | Ascii.Diagram.error()
  def frame(layout, opts) do
    canvas = %{
      grid: Grid.new(layout.cols, layout.rows),
      roles: %{},
      overrides: %{},
      strokes: %{},
      charset: opts[:charset]
    }

    canvas = Enum.reduce(layout.commands, canvas, &draw/2)
    text = canvas.grid |> Grid.to_iodata() |> IO.iodata_to_binary()

    with {:ok, colors, palette} <- palette(canvas, opts) do
      {:ok,
       %Frame{
         text: text,
         lines: String.split(text, "\n"),
         cols: layout.cols,
         rows: layout.rows,
         t: 0.0,
         colors: colors,
         palette: palette
       }}
    end
  end

  defp palette(canvas, opts) do
    if opts[:color] do
      theme = Map.new(opts[:theme], fn {role, color} -> {role, Ink.color(color)} end)

      {indices, {palette, known}} =
        Enum.map_reduce(
          0..(canvas.grid.cols * canvas.grid.rows - 1),
          {[nil], %{nil => 0}},
          fn cell, {palette, known} ->
            ink = Map.get(canvas.overrides, cell) || Map.get(theme, Map.get(canvas.roles, cell))

            case Map.fetch(known, ink) do
              {:ok, index} -> {index, {palette, known}}
              :error -> {map_size(known), {[ink | palette], Map.put(known, ink, map_size(known))}}
            end
          end
        )

      cond do
        map_size(known) > 256 -> {:error, {:too_many_colors, map_size(known)}}
        map_size(known) == 1 -> {:ok, nil, nil}
        true -> {:ok, :binary.list_to_bin(indices), Enum.reverse(palette)}
      end
    else
      {:ok, nil, nil}
    end
  end

  defp draw({:box, %{shape: :diamond} = box, role}, canvas), do: diamond(canvas, box, role)

  defp draw({:box, box, role}, canvas) do
    style = if canvas.charset == :ascii, do: :ascii, else: box_style(box.shape)

    picture =
      box.lines
      |> Compose.text(width: box.width - 4, align: :center)
      |> Compose.panel(style: style)

    canvas =
      Enum.reduce(Enum.with_index(picture.lines), canvas, fn {line, y}, acc ->
        line
        |> String.codepoints()
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {ch, x}, acc ->
          ink = if x in [0, box.width - 1] or y in [0, box.height - 1], do: role, else: :label
          put(acc, box.x + x, box.y + y, ch, ink, Style.ink(box, ink))
        end)
      end)

    canvas
  end

  defp draw({:boundary, box}, canvas), do: draw_border(canvas, box, :boundary)
  defp draw({:fragment, box}, canvas), do: draw_border(canvas, box, :fragment)

  defp draw({:divider, x1, x2, y, label, record}, canvas) do
    ch = if canvas.charset == :ascii, do: "-", else: "┄"

    canvas =
      Enum.reduce(x1..x2, canvas, &put(&2, &1, y, ch, :fragment, Style.ink(record, :fragment)))

    text(canvas, x1 + 2, y, [" " <> label <> " "], :fragment, Style.ink(record, :label))
  end

  defp draw({:activation, box}, canvas) do
    ch = if canvas.charset == :ascii, do: "#", else: "█"

    Enum.reduce(box.y..(box.y + box.height - 1), canvas, fn y, canvas ->
      Enum.reduce(
        box.x..(box.x + box.width - 1),
        canvas,
        &put(&2, &1, y, ch, :activation, Style.ink(box, :activation))
      )
    end)
  end

  defp draw({:text, x, y, lines, role}, canvas), do: text(canvas, x, y, lines, role)
  defp draw({:text, x, y, lines, role, color}, canvas), do: text(canvas, x, y, lines, role, color)

  defp draw({:lifeline, x, y1, y2}, canvas), do: draw({:lifeline, x, y1, y2, nil}, canvas)

  defp draw({:lifeline, x, y1, y2, color}, canvas) do
    ch = if canvas.charset == :ascii, do: ":", else: "┆"
    Enum.reduce(y1..y2//1, canvas, &put(&2, x, &1, ch, :lifeline, color))
  end

  defp draw({:path, edge}, canvas) do
    points =
      edge.points |> Enum.chunk_every(2, 1, :discard) |> Enum.flat_map(&segment/1) |> Enum.dedup()

    neighbors = Enum.zip([hd(points) | Enum.drop(points, -1)], tl(points) ++ [List.last(points)])

    canvas =
      Enum.zip(points, neighbors)
      |> Enum.reduce(canvas, fn {{x, y} = p, {before, after_point}}, acc ->
        directions =
          MapSet.new([direction(p, before), direction(p, after_point)]) |> MapSet.delete(nil)

        stroke(acc, x, y, directions, edge)
      end)

    if edge.arrow and length(points) > 1 do
      {x, y} = List.last(points)
      ch = arrow(canvas.charset, direction(Enum.at(points, -2), {x, y}))
      put(canvas, x, y, ch, :edge, Style.ink(edge, :edge))
    else
      canvas
    end
  end

  defp draw_border(canvas, box, role) do
    {tl, tr, bl, br, h, v} = border(canvas.charset)
    x2 = box.x + box.width - 1
    y2 = box.y + box.height - 1
    ink = Style.ink(box, role)
    canvas = Enum.reduce(box.x..x2, canvas, &put(&2, &1, box.y, h, role, ink))
    canvas = Enum.reduce(box.x..x2, canvas, &put(&2, &1, y2, h, role, ink))
    canvas = Enum.reduce(box.y..y2, canvas, &put(&2, box.x, &1, v, role, ink))
    canvas = Enum.reduce(box.y..y2, canvas, &put(&2, x2, &1, v, role, ink))
    canvas = canvas |> put(box.x, box.y, tl, role, ink) |> put(x2, box.y, tr, role, ink)
    canvas = canvas |> put(box.x, y2, bl, role, ink) |> put(x2, y2, br, role, ink)
    [first | rest] = Map.get(box, :header_lines, String.split(box.label, "\n"))

    canvas =
      text(canvas, box.x + 2, box.y, [" " <> first <> " "], role, Style.ink(box, :label) || ink)

    text(canvas, box.x + 2, box.y + 1, rest, role, Style.ink(box, :label) || ink)
  end

  defp segment([{x, y1}, {x, y2}]), do: for(y <- y1..y2//step(y1, y2), do: {x, y})
  defp segment([{x1, y}, {x2, y}]), do: for(x <- x1..x2//step(x1, x2), do: {x, y})
  defp step(first, last) when first > last, do: -1
  defp step(_first, _last), do: 1

  defp direction({x, y}, {x, y}), do: nil
  defp direction({x, _y}, {x2, _}) when x2 > x, do: :east
  defp direction({x, _y}, {x2, _}) when x2 < x, do: :west
  defp direction({_x, y}, {_x2, y2}) when y2 > y, do: :south
  defp direction(_point, _other), do: :north

  defp stroke(canvas, x, y, directions, edge) do
    key = y * canvas.grid.cols + x
    previous = Map.get(canvas.strokes, key)

    ch =
      if previous && elem(previous, 0) != edge.id,
        do: crossing(canvas.charset),
        else: glyph(canvas.charset, directions, edge.style)

    canvas = put(canvas, x, y, ch, :edge, Style.ink(edge, :edge))
    %{canvas | strokes: Map.put(canvas.strokes, key, {edge.id, directions})}
  end

  defp glyph(:ascii, dirs, style) do
    horizontal? = Enum.all?(dirs, &(&1 in [:east, :west]))
    vertical? = Enum.all?(dirs, &(&1 in [:north, :south]))

    cond do
      style == :dashed and horizontal? -> "."
      horizontal? -> "-"
      vertical? -> "|"
      true -> "+"
    end
  end

  defp glyph(:unicode, dirs, style) do
    case Enum.sort(dirs) do
      [:east] -> line(style, :horizontal)
      [:west] -> line(style, :horizontal)
      [:east, :west] -> line(style, :horizontal)
      [:north] -> line(style, :vertical)
      [:south] -> line(style, :vertical)
      [:north, :south] -> line(style, :vertical)
      [:east, :south] -> "┌"
      [:south, :west] -> "┐"
      [:east, :north] -> "└"
      [:north, :west] -> "┘"
      _ -> "┼"
    end
  end

  defp line(:solid, :horizontal), do: "─"
  defp line(:dashed, :horizontal), do: "┄"
  defp line(:solid, :vertical), do: "│"
  defp line(:dashed, :vertical), do: "┆"
  defp crossing(:ascii), do: "x"
  defp crossing(:unicode), do: "╳"
  defp arrow(:ascii, :east), do: ">"
  defp arrow(:ascii, :west), do: "<"
  defp arrow(:ascii, :north), do: "^"
  defp arrow(:ascii, :south), do: "v"
  defp arrow(:unicode, :east), do: "▶"
  defp arrow(:unicode, :west), do: "◀"
  defp arrow(:unicode, :north), do: "▲"
  defp arrow(:unicode, :south), do: "▼"

  defp diamond(canvas, box, role) do
    mid = div(box.height - 1, 2)
    center = div(box.width - 1, 2)

    canvas =
      Enum.reduce(0..(box.height - 1), canvas, fn y, acc ->
        span = div(center * min(y, box.height - 1 - y), mid)
        left = center - span
        right = box.width - 1 - left

        {l, r} =
          cond do
            y == 0 or y == box.height - 1 -> {"+", "+"}
            y == mid -> {"<", ">"}
            y < mid -> {"/", "\\"}
            true -> {"\\", "/"}
          end

        acc
        |> put(box.x + left, box.y + y, l, role, Style.ink(box, role))
        |> put(box.x + right, box.y + y, r, role, Style.ink(box, role))
      end)

    top = div(box.height - length(box.lines), 2)

    Enum.reduce(Enum.with_index(box.lines), canvas, fn {line, row}, acc ->
      text(
        acc,
        box.x + div(box.width - Text.width(line), 2),
        box.y + top + row,
        [line],
        :label,
        Style.ink(box, :label)
      )
    end)
  end

  defp text(canvas, x, y, lines, role, color \\ nil) do
    Enum.reduce(Enum.with_index(lines), canvas, fn {line, row}, acc ->
      line
      |> String.codepoints()
      |> Enum.with_index(x)
      |> Enum.reduce(acc, fn {ch, col}, acc -> put(acc, col, y + row, ch, role, color) end)
    end)
  end

  defp put(canvas, x, y, ch, role, color) do
    %{
      canvas
      | grid: Grid.put(canvas.grid, x, y, ch),
        roles: Map.put(canvas.roles, y * canvas.grid.cols + x, role),
        overrides:
          if(color,
            do: Map.put(canvas.overrides, y * canvas.grid.cols + x, color),
            else: Map.delete(canvas.overrides, y * canvas.grid.cols + x)
          )
    }
  end

  defp box_style(:rounded), do: :rounded
  defp box_style(_shape), do: :single
  defp border(:ascii), do: {"+", "+", "+", "+", "-", "|"}
  defp border(:unicode), do: {"┌", "┐", "└", "┘", "─", "│"}
end
