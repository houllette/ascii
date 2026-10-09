defmodule Ascii.RenderTest do
  use ExUnit.Case, async: true

  alias Ascii.Frame
  alias Ascii.Render.{ANSI, HTML, SVG, Text}

  # Two rows of three: "ab " in red, red, blue; "c d" in blue, blue, red.
  @frame %Frame{
    text: "ab \nc d",
    lines: ["ab ", "c d"],
    colors: <<0, 0, 1, 1, 1, 0>>,
    palette: ["#ff0000", "#0000ff"],
    ground: "#101010",
    cols: 3,
    rows: 2,
    t: 0.0
  }

  @text_frame %Frame{text: "x \n y", lines: ["x ", " y"], cols: 2, rows: 2, t: 0.0}

  describe "Text" do
    test "is the frame's text" do
      assert IO.iodata_to_binary(Text.render(@frame)) == "ab \nc d"
    end
  end

  describe "ANSI" do
    test "truecolor: one escape a run of colour, the ground behind, reset at each line's end" do
      out = IO.iodata_to_binary(ANSI.render(@frame))

      assert out ==
               "\e[48;2;16;16;16m\e[38;2;255;0;0mab \e[0m\n" <>
                 "\e[48;2;16;16;16m\e[38;2;0;0;255mc \e[38;2;255;0;0md\e[0m"
    end

    test "a space takes whatever colour is current, so it never starts a run" do
      out = IO.iodata_to_binary(ANSI.render(@frame, ground: false))
      # The space in row 2 has colour 0, but stays in the blue run before it.
      assert out == "\e[38;2;255;0;0mab \e[0m\n\e[38;2;0;0;255mc \e[38;2;255;0;0md\e[0m"
    end

    test "ansi256 maps to the nearest xterm colour" do
      out = IO.iodata_to_binary(ANSI.render(@frame, mode: :ansi256, ground: false))
      assert out =~ "\e[38;5;196mab"
      assert out =~ "\e[38;5;21mc"
      assert ANSI.xterm256({128, 128, 128}) in 232..255
      assert ANSI.xterm256({0, 0, 0}) == 16
    end

    test "mono is plain text" do
      assert IO.iodata_to_binary(ANSI.render(@frame, mode: :mono)) == "ab \nc d"
    end

    test "a frame without colours is plain text in every mode" do
      for mode <- [:truecolor, :ansi256, :mono] do
        assert IO.iodata_to_binary(ANSI.render(@text_frame, mode: mode)) == "x \n y"
      end
    end

    test "terminal control" do
      assert ANSI.home() == "\e[H"
      assert ANSI.hide_cursor() == "\e[?25l"
      assert ANSI.show_cursor() == "\e[?25h"
      assert ANSI.clear() == "\e[2J"
      assert ANSI.reset() == "\e[0m"
    end

    test "changes: from nothing, every row, each placed" do
      out = IO.iodata_to_binary(ANSI.changes(nil, @text_frame))
      assert out == "\e[1;1Hx \e[2;1H y"
    end

    test "changes: only the runs that changed, placed; nothing when nothing did" do
      before = @text_frame
      now = %{@text_frame | text: "x \n z", lines: ["x ", " z"]}
      assert IO.iodata_to_binary(ANSI.changes(before, now)) == "\e[2;2Hz"
      assert IO.iodata_to_binary(ANSI.changes(now, now)) == ""
    end

    test "changes: a coloured run in its colours over the ground, then reset" do
      now = %{@frame | text: "ab \ncXd", lines: ["ab ", "cXd"], colors: <<0, 0, 1, 1, 0, 0>>}
      out = IO.iodata_to_binary(ANSI.changes(@frame, now))
      assert out == "\e[2;2H\e[48;2;16;16;16m\e[38;2;255;0;0mX\e[0m"

      assert IO.iodata_to_binary(ANSI.changes(@frame, now, mode: :mono)) == "\e[2;2HX"
    end

    test "changes: placed from another corner" do
      out = IO.iodata_to_binary(ANSI.changes(nil, @text_frame, at: {5, 10}))
      assert out == "\e[5;10Hx \e[6;10H y"
    end

    test "changes over a real piece write far less than whole frames" do
      anim = Ascii.new!("night-coast")
      {a, anim} = Ascii.frame(anim, 1.0)
      {b, _anim} = Ascii.frame(anim, 1.1)
      whole = b |> ANSI.render() |> IO.iodata_to_binary() |> byte_size()
      delta = a |> ANSI.changes(b) |> IO.iodata_to_binary() |> byte_size()
      assert delta * 4 < whole
    end

    test "a real coloured piece renders every cell" do
      {:ok, anim} = Ascii.new("elixir")
      {frame, _} = Ascii.frame(anim, 0)
      out = IO.iodata_to_binary(ANSI.render(frame))
      stripped = String.replace(out, ~r/\e\[[0-9;]*m/, "")
      assert stripped == frame.text
    end
  end

  describe "HTML" do
    test "runs of one colour as spans, spaces joining the run they fall in" do
      assert IO.iodata_to_binary(HTML.render(@frame)) ==
               ~s(<span style="color:#ff0000">ab </span>\n<span style="color:#0000ff">c </span><span style="color:#ff0000">d</span>)
    end

    test "text is escaped" do
      frame = %{@text_frame | text: "<&\n\">", lines: ["<&", "\">"]}
      assert IO.iodata_to_binary(HTML.render(frame)) == "&lt;&amp;\n&quot;&gt;"
    end

    test "a frame without colours is its escaped text" do
      assert IO.iodata_to_binary(HTML.render(@text_frame)) == "x \n y"
    end

    test "the style for the pre: the ground behind a coloured frame" do
      assert HTML.style(@frame) == "background:#101010"
      assert HTML.style(@text_frame) == nil
    end

    test "row by row, as render/1 joins them" do
      html = &Enum.map(&1, fn row -> IO.iodata_to_binary(row) end)

      assert html.(HTML.rows(@frame)) == [
               ~s(<span style="color:#ff0000">ab </span>),
               ~s(<span style="color:#0000ff">c </span><span style="color:#ff0000">d</span>)
             ]

      assert html.(HTML.rows(%{@text_frame | lines: ["<&", " y"]})) == ["&lt;&amp;", " y"]

      for frame <- [@frame, @text_frame], y <- 0..1 do
        assert IO.iodata_to_binary(HTML.row(frame, y)) == Enum.at(html.(HTML.rows(frame)), y)
      end
    end
  end

  describe "SVG" do
    defp svg(frame, opts \\ []), do: frame |> SVG.render(opts) |> IO.iodata_to_binary()

    # Well-formed XML, or it raises.
    defp parse(svg) do
      {doc, _rest} = svg |> :binary.bin_to_list() |> :xmerl_scan.string(quiet: true)
      doc
    end

    test "a run of one colour a tspan, placed at its column and held to its width" do
      out = svg(@frame)

      assert out =~
               ~s(<text y="8.4" dominant-baseline="central" xml:space="preserve"><tspan x="0" textLength="16.8" lengthAdjust="spacingAndGlyphs" fill="#ff0000">ab</tspan></text>)

      assert out =~
               ~s(<tspan x="0" textLength="8.4" lengthAdjust="spacingAndGlyphs" fill="#0000ff">c</tspan><tspan x="16.8" textLength="8.4" lengthAdjust="spacingAndGlyphs" fill="#ff0000">d</tspan>)

      assert out =~ ~s(width="25.2" height="33.6" viewBox="0 0 25.2 33.6")
      parse(out)
    end

    test "words a space apart are one run; two spaces or more part runs" do
      lines = ["a b  c   d"]
      frame = %Frame{text: hd(lines), lines: lines, cols: 10, rows: 1, t: 0.0}
      out = svg(frame, font_size: 10)
      assert out =~ ~s(<tspan x="0" textLength="18" lengthAdjust="spacingAndGlyphs">a b</tspan>)
      assert out =~ ~s(<tspan x="30" textLength="6" lengthAdjust="spacingAndGlyphs">c</tspan>)
      assert out =~ ~s(<tspan x="54" textLength="6" lengthAdjust="spacingAndGlyphs">d</tspan>)
    end

    test "over the ground, or another background, or none" do
      assert svg(@frame) =~ ~s(<rect width="100%" height="100%" fill="#101010"/>)
      assert svg(@frame, background: "#fff") =~ ~s(fill="#fff"/>)
      refute svg(@text_frame) =~ "<rect"
      refute svg(%{@frame | ground: nil}) =~ "<rect"
    end

    test "uncoloured text in the foreground; spaces left out; text escaped" do
      out = svg(%{@text_frame | lines: ["<&", " y"]}, foreground: "#333333")
      assert out =~ ~s(<g font-family="ui-monospace)
      assert out =~ ~s(fill="#333333">)

      assert out =~
               ~s(<tspan x="0" textLength="16.8" lengthAdjust="spacingAndGlyphs">&lt;&amp;</tspan>)

      assert out =~ ~s(<tspan x="8.4" textLength="8.4" lengthAdjust="spacingAndGlyphs">y</tspan>)
      parse(out)
    end

    test "a cell as tall as the piece's cell says, at the font size asked" do
      out = svg(%{@text_frame | cell: 1}, font_size: 10)
      assert out =~ ~s(width="12" height="12")
      assert out =~ ~s(font-size="10")
    end

    test "a title for screen readers, escaped" do
      out = svg(@frame, title: ~s(a "red" & blue))
      assert out =~ ~s(aria-label="a &quot;red&quot; &amp; blue">)
      assert out =~ "<title>a &quot;red&quot; &amp; blue</title>"
      parse(out)
    end

    test "a CSS variable stays one, with the foreground as its fallback if it has none" do
      frame = %{@frame | palette: ["var(--a, #ff0000)", "var(--b)"]}
      out = svg(frame)
      assert out =~ ~s|style="fill:var(--a, #ff0000)"|
      assert out =~ ~s|style="fill:var(--b, currentColor)"|
    end

    test "a real piece, in colour and in an ink with parts, is well-formed" do
      for opts <- [[], [parts: true, ink: "#c9d1d9"]], piece <- ["night-coast", "boot-log"] do
        {:ok, frame} = Ascii.still(piece, opts)
        doc = frame |> svg(title: piece) |> parse()
        assert elem(doc, 0) == :xmlElement
      end
    end
  end
end
