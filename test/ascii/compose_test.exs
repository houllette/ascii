defmodule Ascii.ComposeTest do
  use ExUnit.Case, async: true

  alias Ascii.{Compose, Frame}
  alias Ascii.Render.{ANSI, HTML}

  # "ab" over "cd": a red, b blue, c and d in the renderer's own ink.
  @frame %Frame{
    text: "ab\ncd",
    lines: ["ab", "cd"],
    colors: <<0, 1, 2, 2>>,
    palette: ["#ff0000", "#0000ff", nil],
    cols: 2,
    rows: 2,
    t: 1.5
  }

  @plain %Frame{text: "xyz", lines: ["xyz"], cols: 3, rows: 1, t: 0.0}

  defp colours(%Frame{colors: nil} = frame), do: List.duplicate(nil, frame.cols * frame.rows)

  defp colours(%Frame{} = frame),
    do: for(y <- 0..(frame.rows - 1), x <- 0..(frame.cols - 1), do: Frame.color_at(frame, x, y))

  # Every frame keeps the contract: rows of cols characters, a colour each.
  defp assert_frame(%Frame{} = frame) do
    assert length(frame.lines) == frame.rows
    assert frame.text == Enum.join(frame.lines, "\n")
    for line <- frame.lines, do: assert(String.length(line) == frame.cols)
    if frame.colors, do: assert(byte_size(frame.colors) == frame.cols * frame.rows)
    frame
  end

  describe "text/2" do
    test "lines padded to the longest, in the renderer's own ink" do
      frame = assert_frame(Compose.text(["pid", "12345"]))
      assert frame.lines == ["pid  ", "12345"]
      assert frame.colors == nil
    end

    test "cut or padded to a width, aligned, in a colour" do
      frame = assert_frame(Compose.text("hello\nhi", width: 4, align: :right, color: "#abc"))
      assert frame.lines == ["hell", "  hi"]
      assert Frame.color_at(frame, 3, 1) == "#aabbcc"
    end

    test "a colour that is not one is refused" do
      assert_raise ArgumentError, fn -> Compose.text("x", color: "red") end
    end
  end

  describe "divider/2" do
    test "a rule across the width, in any style" do
      assert Compose.divider(5).lines == ["─────"]
      assert Compose.divider(5, style: :dotted).lines == ["· · ·"]
      assert Compose.divider(7, style: :wave).lines == ["_.·°·._"]
    end

    test "a label set into it, a space either side, in its own colour" do
      frame =
        assert_frame(Compose.divider(16, label: "logs", color: "#888888", label_color: "#fff"))

      assert frame.lines == ["── logs ────────"]
      assert Frame.color_at(frame, 0, 0) == "#888888"
      assert Frame.color_at(frame, 3, 0) == "#ffffff"
      assert Frame.color_at(frame, 8, 0) == "#888888"

      assert Compose.divider(16, label: "logs", align: :center).lines == ["───── logs ─────"]
      assert Compose.divider(16, label: "logs", align: :right).lines == ["──────── logs ──"]
    end

    test "a label too long for the rule is cut" do
      frame = assert_frame(Compose.divider(10, label: "a very long label"))
      assert frame.lines == ["── a ve ──"]
    end
  end

  describe "panel/2" do
    test "a box around the frame, padded at the sides, its title in the top edge" do
      frame = assert_frame(Compose.panel(@plain, title: "x"))
      assert frame.lines == ["╭─ x ─╮", "│ xyz │", "╰─────╯"]
      assert frame.colors == nil
    end

    test "wide enough for its title; the frame centred, its colours kept" do
      frame = assert_frame(Compose.panel(@frame, title: "colours", style: :single, color: "#444"))

      assert frame.lines == [
               "┌─ colours ─┐",
               "│    ab     │",
               "│    cd     │",
               "└───────────┘"
             ]

      assert Frame.color_at(frame, 5, 1) == "#ff0000"
      assert Frame.color_at(frame, 6, 1) == "#0000ff"
      assert Frame.color_at(frame, 5, 2) == nil
      assert Frame.color_at(frame, 0, 1) == "#444444"
      assert Frame.color_at(frame, 3, 0) == nil
      assert frame.t == 1.5
    end

    test "a given size, the frame placed in it; never smaller than the frame" do
      frame = assert_frame(Compose.panel(@plain, width: 9, height: 5, align: :left, valign: :top))
      assert frame.lines == ["╭───────╮", "│ xyz   │", "│       │", "│       │", "╰───────╯"]

      assert Compose.panel(@plain, width: 2, height: 2).lines ==
               Compose.panel(@plain).lines
    end

    test "every style" do
      for style <- [:single, :double, :rounded, :heavy, :dashed, :ascii, :block] do
        assert_frame(Compose.panel(@frame, style: style, padding: 0, padding_y: 1))
      end

      assert Compose.panel(@plain, style: :ascii, padding: 0).lines == ["+---+", "|xyz|", "+---+"]
    end
  end

  describe "beside/2 and above/2" do
    test "side by side, a gap apart, tops level; colours from each" do
      frame = assert_frame(Compose.beside([@frame, @plain], gap: 2))
      assert frame.lines == ["ab  xyz", "cd     "]
      assert Enum.take(colours(frame), 7) == ["#ff0000", "#0000ff", nil, nil, nil, nil, nil]
    end

    test "aligned at the bottom or the middle" do
      assert Compose.beside([@frame, @plain], align: :bottom, gap: 0).lines == ["ab   ", "cdxyz"]
      tall = Compose.above([@plain, @plain, @plain])

      assert Compose.beside([tall, @plain], align: :middle).lines == [
               "xyz    ",
               "xyz xyz",
               "xyz    "
             ]
    end

    test "one above another, a gap apart, aligned" do
      frame = assert_frame(Compose.above([@frame, @plain], gap: 1, align: :right))
      assert frame.lines == [" ab", " cd", "   ", "xyz"]
      assert Frame.color_at(frame, 1, 0) == "#ff0000"
    end

    test "a palette holds each colour once, however many frames share it" do
      frame = Compose.beside([@frame, @frame, @frame])
      assert frame.palette == [nil, "#ff0000", "#0000ff"]
    end

    test "a ground kept where all coloured frames share it, else dropped unless given" do
      dark = %{@frame | ground: "#000000"}
      assert Compose.beside([dark, @plain]).ground == "#000000"
      assert Compose.beside([dark, %{@frame | ground: "#111111"}]).ground == nil
      assert Compose.above([dark, @frame], ground: "#222222").ground == "#222222"
    end

    test "real pieces nest, and render" do
      {:ok, gauge} = Ascii.still("gauge", parts: true)
      {:ok, logo} = Ascii.still("elixir")

      frame =
        Compose.above([
          Compose.beside([
            Compose.panel(gauge, title: "load"),
            Compose.panel(logo, title: "logo")
          ]),
          Compose.divider(40, label: "end")
        ])

      assert_frame(frame)
      assert IO.iodata_to_binary(ANSI.render(frame)) =~ "load"
      assert IO.iodata_to_binary(HTML.render(frame)) =~ "<span"
    end
  end

  describe "fit/4" do
    test "a smaller frame placed in the room" do
      frame = assert_frame(Compose.fit(@plain, 5, 3))
      assert frame.lines == ["     ", " xyz ", "     "]
      assert Compose.fit(@plain, 5, 2, align: :right, valign: :bottom).lines == ["     ", "  xyz"]
    end

    test "a larger one cut to its middle, or as aligned" do
      assert Compose.fit(@frame, 1, 1).lines == ["a"]
      assert Compose.fit(@frame, 1, 1, align: :right, valign: :bottom).lines == ["d"]
      assert Frame.color_at(Compose.fit(@frame, 1, 1, align: :right), 0, 0) == "#0000ff"
      assert Compose.fit(@plain, 2, 3, align: :left).lines == ["  ", "xy", "  "]
    end
  end
end
