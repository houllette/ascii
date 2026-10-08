defmodule AsciiArt.ExRatatuiTest do
  use ExUnit.Case, async: true

  alias AsciiArt.{Frame, Render}
  alias AsciiArt.Kit.Palette
  alias ExRatatui.CellSession
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Paragraph}

  # Two rows of four cells in two inks, over a dark ground.
  @frame %Frame{
    text: "ab c\n  dd",
    lines: ["ab c", "  dd"],
    colors: <<0, 1, 1, 0, 1, 0, 1, 1>>,
    palette: ["#ff0000", "#00ff00"],
    ground: "#000010",
    cols: 4,
    rows: 2,
    t: 0.0
  }

  @red {:rgb, 255, 0, 0}
  @green {:rgb, 0, 255, 0}

  # A frame whose every cell differs from its neighbours', so a picture
  # drawn a cell out of place shows it.
  defp grid(cols, rows) do
    lines =
      for y <- 0..(rows - 1),
          do: for(x <- 0..(cols - 1), into: "", do: <<?a + rem(x + 7 * y, 26)>>)

    %Frame{
      text: Enum.join(lines, "\n"),
      lines: lines,
      colors: :binary.copy(<<0>>, cols * rows),
      palette: ["#ffffff"],
      ground: "#202020",
      cols: cols,
      rows: rows,
      t: 0.0
    }
  end

  defp spans(line), do: Enum.map(line.spans, &{&1.content, &1.style.fg})

  # The cells that placed widgets paint, by {x, y}.
  defp draw(widgets, width, height) do
    session = CellSession.new(width, height)
    :ok = CellSession.draw(session, widgets)
    snapshot = CellSession.take_cells(session)
    CellSession.close(session)
    Map.new(snapshot.cells, &{{&1.col, &1.row}, &1})
  end

  defp char_at(frame, x, y), do: frame.lines |> Enum.at(y) |> String.at(x)

  defp rgb(hex) do
    {r, g, b} = Palette.rgb255(hex)
    {:rgb, r, g, b}
  end

  # Asserts the frame's cells from `{fx, fy}` are drawn from `{x, y}` on, for
  # `w` by `h` cells.
  defp assert_drawn(cells, frame, {x, y}, {fx, fy}, {w, h}) do
    for dy <- 0..(h - 1), dx <- 0..(w - 1) do
      assert cells[{x + dx, y + dy}].symbol == char_at(frame, fx + dx, fy + dy),
             "frame cell #{fx + dx}, #{fy + dy}"
    end
  end

  describe "lines/2" do
    test "a span a run of one ink, the ground behind each line" do
      [first, second] = AsciiArt.ExRatatui.lines(@frame)
      assert spans(first) == [{"a", @red}, {"b ", @green}, {"c", @red}]
      assert first.style.bg == {:rgb, 0, 0, 16}
      # A space has no ink to show, so it joins whatever run it is in.
      assert spans(second) == [{"  dd", @green}]
    end

    test "characters of more than one byte" do
      frame = %{@frame | text: "█▒ é\nab▒▒", lines: ["█▒ é", "ab▒▒"]}
      [first, second] = AsciiArt.ExRatatui.lines(frame)
      assert spans(first) == [{"█", @red}, {"▒ ", @green}, {"é", @red}]
      assert spans(second) == [{"a", @green}, {"b", @red}, {"▒▒", @green}]
    end

    test "the nearest of xterm's 256 colours, for terminals without 24-bit colour" do
      [first, _] = AsciiArt.ExRatatui.lines(@frame, mode: :ansi256)
      red = {:indexed, Render.ANSI.xterm256({255, 0, 0})}
      assert [{"a", ^red} | _] = spans(first)
      assert first.style.bg == {:indexed, Render.ANSI.xterm256({0, 0, 16})}
    end

    test "in one ink, or without the ground" do
      assert @frame |> AsciiArt.ExRatatui.lines(mode: :mono) |> Enum.map(&spans/1) ==
               [[{"ab c", nil}], [{"  dd", nil}]]

      [first, _] = AsciiArt.ExRatatui.lines(@frame, ground: false)
      assert first.style.bg == nil
      assert spans(first) == [{"a", @red}, {"b ", @green}, {"c", @red}]
    end

    test "a text piece is its lines, in the terminal's own colours" do
      {:ok, frame} = AsciiArt.still("spinners")
      lines = AsciiArt.ExRatatui.lines(frame)
      assert Enum.map(lines, &spans/1) == Enum.map(frame.lines, &[{&1, nil}])
    end
  end

  describe "drawn" do
    test "every cell has its character and its ink" do
      {:ok, frame} = AsciiArt.still("elixir")
      rect = %Rect{x: 0, y: 0, width: frame.cols, height: frame.rows}
      cells = draw([{AsciiArt.ExRatatui.paragraph(frame), rect}], frame.cols, frame.rows)
      assert_drawn(cells, frame, {0, 0}, {0, 0}, {frame.cols, frame.rows})

      for y <- 0..(frame.rows - 1), x <- 0..(frame.cols - 1), char_at(frame, x, y) != " " do
        assert cells[{x, y}].fg == rgb(Frame.color_at(frame, x, y)), "at #{x}, #{y}"
      end
    end

    test "every cell over the ground" do
      cells =
        draw(
          [{AsciiArt.ExRatatui.paragraph(@frame), %Rect{x: 0, y: 0, width: 4, height: 2}}],
          4,
          2
        )

      assert cells |> Map.values() |> Enum.map(& &1.bg) |> Enum.uniq() == [{:rgb, 0, 0, 16}]
    end

    test "a frame is a widget itself" do
      {:ok, frame} = AsciiArt.still("elixir")
      rect = %Rect{x: 2, y: 1, width: frame.cols, height: frame.rows}
      size = {frame.cols + 2, frame.rows + 1}
      cells = draw([{frame, rect}], elem(size, 0), elem(size, 1))

      assert cells ==
               draw([{AsciiArt.ExRatatui.paragraph(frame), rect}], elem(size, 0), elem(size, 1))

      assert_drawn(cells, frame, {2, 1}, {0, 0}, {frame.cols, frame.rows})
    end
  end

  describe "paragraph/2" do
    test "a title puts it in a bordered block; :border without one" do
      assert %Paragraph{block: %Block{title: "Elixir", borders: [:all]}} =
               AsciiArt.ExRatatui.paragraph(@frame, title: "Elixir")

      assert %Paragraph{block: %Block{title: nil, borders: [:all]}} =
               AsciiArt.ExRatatui.paragraph(@frame, border: true)

      assert %Paragraph{block: nil} = AsciiArt.ExRatatui.paragraph(@frame)
    end
  end

  describe "place/3" do
    test "centres it in the area, its border around it" do
      frame = grid(30, 20)
      area = %Rect{x: 0, y: 0, width: 50, height: 40}
      {paragraph, rect} = AsciiArt.ExRatatui.place(frame, area, title: "Grid")
      assert rect == %Rect{x: 9, y: 9, width: 32, height: 22}

      cells = draw([{paragraph, rect}], 50, 40)
      assert cells[{9, 9}].symbol == "┌"
      assert cells[{40, 30}].symbol == "┘"
      assert_drawn(cells, frame, {10, 10}, {0, 0}, {30, 20})
    end

    test "a box wide enough for its title, the picture in the middle of it" do
      area = %Rect{x: 0, y: 0, width: 20, height: 6}
      {paragraph, rect} = AsciiArt.ExRatatui.place(@frame, area, title: "Elixir!")
      assert rect == %Rect{x: 5, y: 1, width: 9, height: 4}

      cells = draw([{paragraph, rect}], 20, 6)
      assert Enum.map_join(5..13, &cells[{&1, 1}].symbol) == "┌Elixir!┐"
      assert Enum.map_join(5..13, &cells[{&1, 2}].symbol) == "│ ab c  │"
    end

    test "within an area away from the origin" do
      area = %Rect{x: 7, y: 3, width: 10, height: 6}
      assert {_, %Rect{x: 10, y: 5, width: 4, height: 2}} = AsciiArt.ExRatatui.place(@frame, area)
    end

    test "too big for the area, it shows its middle" do
      frame = grid(30, 20)
      area = %Rect{x: 4, y: 2, width: 15, height: 9}
      {paragraph, rect} = AsciiArt.ExRatatui.place(frame, area)
      assert rect == area

      cells = draw([{paragraph, rect}], 20, 12)
      assert_drawn(cells, frame, {4, 2}, {7, 5}, {15, 9})
    end

    test "too big with a border, it keeps the border and shows its middle inside" do
      frame = grid(30, 20)
      area = %Rect{x: 0, y: 0, width: 17, height: 11}
      {paragraph, rect} = AsciiArt.ExRatatui.place(frame, area, border: true)
      assert rect == area

      cells = draw([{paragraph, rect}], 17, 11)
      assert cells[{0, 0}].symbol == "┌"
      assert cells[{16, 10}].symbol == "┘"
      assert_drawn(cells, frame, {1, 1}, {7, 5}, {15, 9})
    end

    test "with no room it draws nothing, rather than failing" do
      area = %Rect{x: 3, y: 3, width: 0, height: 0}
      {paragraph, rect} = AsciiArt.ExRatatui.place(@frame, area, title: "x")
      assert rect == area
      assert draw([{paragraph, rect}], 4, 4) |> Map.values() |> Enum.all?(&(&1.symbol == " "))
    end
  end
end
