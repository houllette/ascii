defmodule Ascii.Pieces.BoxFrames do
  @moduledoc """
  Twelve frame styles to copy, each one labelled.

  A sheet of twelve frame styles, from box drawing lines to half blocks, a
  title in the edge, a drop shadow and bare corners. To draw one of these
  boxes around a frame of your own, a piece's or your own text's, see
  `Ascii.Compose.panel/2`.

  ## Options

  It takes no options: the sheet is always the same twelve frames, 78 by
  20, and still (0 frames a second).

  ## Colours

  It has no parts to colour one by one: in one ink, or a gradient, with
  `:ink` and `:gradient` (see `Ascii.Ink`). A diagonal gradient runs
  from corner to corner of the sheet.

  ## Keys and clicks

  It takes none: it is a sheet to copy from, and `Ascii.handle_event/2`
  ignores every event. A Phoenix player given `interactive` and `notify`
  still tells your LiveView where it was clicked.

  ## Screen readers

  `Ascii.describe/1` gives the piece's name and note: "box frames:
  twelve frame styles to copy, each one labelled".

  ## Example

  ```elixir
  {:ok, sheet} = Ascii.still("box-frames", ink: ["#58a6ff", "#a371f7"], gradient: :diagonal)
  {sheet.cols, sheet.rows}
  #=> {78, 20}

  # One of its boxes, around a frame of your own.
  {:ok, gauge} = Ascii.still("gauge", options: %{value: 40})
  panel = Ascii.Compose.panel(gauge, title: "load", style: :double)
  panel.lines |> hd() |> String.starts_with?("╔═ load ═")
  #=> true
  ```

  ```heex
  <Ascii.Phoenix.Components.ascii piece="box-frames" ink="#8b949e" />
  ```

  Ported from `src/pieces/box-frames.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Kit.{Grid, Text}

  @meta %Ascii.Meta{
    name: "box frames",
    category: :ui,
    note: "twelve frame styles to copy, each one labelled",
    cols: 78,
    rows: 20,
    fps: 0
  }

  # One frame, borders included.
  @w 16
  @h 5
  @gap_x 4
  @gap_y 1

  # Corners top left, top right, bottom left, bottom right, then the top and
  # bottom edge, then the sides.
  @lines %{
    "single" => "┌┐└┘──││",
    "double" => "╔╗╚╝══║║",
    "rounded" => "╭╮╰╯──││",
    "heavy" => "┏┓┗┛━━┃┃",
    "dashed" => "┌┐└┘┄┄┆┆",
    "ascii" => "++++--||",
    "mixed" => "╒╕╘╛══││",
    "titled" => "┌┐└┘──││",
    "block" => "▛▜▙▟▀▄▌▐",
    "shadow" => "┌┐└┘──││"
  }

  @sheet ~w(single double rounded heavy dashed ascii mixed titled shade block shadow corners)

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    left = floor((cols - 4 * @w - 3 * @gap_x) / 2)

    grid =
      @sheet
      |> Enum.with_index()
      |> Enum.reduce(Grid.new(cols, rows), fn {name, i}, grid ->
        y = 1 + div(i, 4) * (@h + @gap_y)
        x = left + rem(i, 4) * (@w + @gap_x)
        grid |> style(name, y, x) |> label(name, y, x)
      end)

    IO.iodata_to_binary(Grid.to_iodata(grid))
  end

  defp style(grid, "corners", y, x), do: corners(grid, y, x)
  defp style(grid, "shade", y, x), do: shade(grid, y, x)
  defp style(grid, "shadow", y, x), do: grid |> frame(y, x, @lines["shadow"]) |> shadow(y, x)
  defp style(grid, name, y, x), do: frame(grid, y, x, @lines[name])

  # The titled frame carries its name in the top edge; the rest inside.
  defp label(grid, "titled" = name, y, x), do: write(grid, y, x + 2, " #{name} ")

  defp label(grid, name, y, x),
    do: write(grid, y + 2, x + floor((@w - Text.length(name)) / 2), name)

  defp put(grid, r, c, ch), do: Grid.put(grid, c, r, ch)
  defp write(grid, r, c, s), do: Grid.put_string(grid, c, r, s)

  defp frame(grid, y, x, g) do
    g = g |> String.codepoints() |> List.to_tuple()

    grid =
      Enum.reduce((x + 1)..(x + @w - 2)//1, grid, fn c, grid ->
        grid |> put(y, c, elem(g, 4)) |> put(y + @h - 1, c, elem(g, 5))
      end)

    grid =
      Enum.reduce((y + 1)..(y + @h - 2)//1, grid, fn r, grid ->
        grid |> put(r, x, elem(g, 6)) |> put(r, x + @w - 1, elem(g, 7))
      end)

    grid
    |> put(y, x, elem(g, 0))
    |> put(y, x + @w - 1, elem(g, 1))
    |> put(y + @h - 1, x, elem(g, 2))
    |> put(y + @h - 1, x + @w - 1, elem(g, 3))
  end

  # A border of light shade, two columns wide at the sides so it is as thick
  # as the one-row top and bottom, a cell being twice as tall as it is wide.
  defp shade(grid, y, x) do
    grid =
      Enum.reduce(x..(x + @w - 1)//1, grid, fn c, grid ->
        grid |> put(y, c, "░") |> put(y + @h - 1, c, "░")
      end)

    for r <- (y + 1)..(y + @h - 2)//1,
        c <- [x, x + 1, x + @w - 2, x + @w - 1],
        reduce: grid,
        do: (grid -> put(grid, r, c, "░"))
  end

  # Only the corners, each with a short arm along the top or bottom edge.
  defp corners(grid, y, x) do
    r = x + @w - 1
    b = y + @h - 1

    grid
    |> write(y, x, "┌──")
    |> write(y, r - 2, "──┐")
    |> write(b, x, "└──")
    |> write(b, r - 2, "──┘")
  end

  # A shadow one row down and two columns over, so it falls square.
  defp shadow(grid, y, x) do
    grid =
      Enum.reduce((y + 1)..(y + @h)//1, grid, fn r, grid ->
        grid |> put(r, x + @w, "▒") |> put(r, x + @w + 1, "▒")
      end)

    Enum.reduce((x + 2)..(x + @w - 1)//1, grid, fn c, grid -> put(grid, y + @h, c, "▒") end)
  end

  @impl true
  def frame(picture, _t, _env), do: {picture, nil, picture}
end
