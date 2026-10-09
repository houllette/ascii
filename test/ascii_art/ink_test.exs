defmodule AsciiArt.InkTest do
  use ExUnit.Case, async: true

  doctest AsciiArt.Ink

  alias AsciiArt.{Frame, Ink}
  alias AsciiArt.Render.{ANSI, HTML}

  defp frame(lines, cell \\ 2) do
    %Frame{
      text: Enum.join(lines, "\n"),
      lines: lines,
      cols: String.length(hd(lines)),
      rows: length(lines),
      cell: cell,
      t: 0.0
    }
  end

  defp ink!(colors, gradient \\ nil) do
    {:ok, ink} = Ink.cast(colors, gradient)
    ink
  end

  # Each cell's colour, row by row.
  defp colours(%Frame{cols: cols, rows: rows} = frame),
    do: for(y <- 0..(rows - 1), do: for(x <- 0..(cols - 1), do: Frame.color_at(frame, x, y)))

  describe "cast/2" do
    test "one colour, or several, as #rrggbb" do
      assert Ink.cast("#FF8800") == {:ok, %Ink{colors: ["#ff8800"], gradient: :horizontal}}
      assert {:ok, %Ink{colors: ["#ff8800"]}} = Ink.cast("#f80")
      assert {:ok, %Ink{colors: ["#ff8800"]}} = Ink.cast("ff8800")
      assert {:ok, %Ink{colors: ["#ff5f6d", "#ffc371"]}} = Ink.cast(["#ff5f6d", "#ffc371"])
      assert {:ok, %Ink{colors: ["#ff5f6d", "#ffc371"]}} = Ink.cast("#ff5f6d, #ffc371")
    end

    test "none at all is no ink" do
      for none <- [nil, "", " ", []], do: assert(Ink.cast(none) == {:ok, nil})
    end

    test "which way several run" do
      assert {:ok, %Ink{gradient: :vertical}} = Ink.cast("#fff,#000", :vertical)
      assert {:ok, %Ink{gradient: :diagonal}} = Ink.cast("#fff,#000", "diagonal")
      assert {:ok, %Ink{gradient: :horizontal}} = Ink.cast("#fff,#000", "")
    end

    test "anything else is refused, and makes no atom" do
      for bad <- ["red", "#ff88", "#gg0000", ["#fff", 1], 42, List.duplicate("#fff", 17)] do
        assert Ink.cast(bad) == {:error, {:invalid_option, :ink}}, inspect(bad)
      end

      for bad <- ["sideways", :sideways, 1] do
        assert Ink.cast("#fff", bad) == {:error, {:invalid_option, :gradient}}, inspect(bad)
      end

      name = "ink_direction_#{System.unique_integer([:positive])}"
      assert Ink.cast("#fff", name) == {:error, {:invalid_option, :gradient}}
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end

  describe "CSS variables" do
    test "one ink can be a variable, with or without a fallback; several cannot" do
      assert {:ok, %Ink{colors: ["var(--accent)"]}} = Ink.cast("var(--accent)")

      assert {:ok, %Ink{colors: ["var(--accent, #ff8800)"]}} =
               Ink.cast(["var(--accent,#f80)"])

      assert Ink.cast(["var(--a)", "#fff"]) == {:error, {:invalid_option, :ink}}
      assert Ink.cast("var(--a), #fff") == {:error, {:invalid_option, :ink}}
    end

    test "nothing that could break out of a style attribute is a colour" do
      for bad <- [~s{var(--a);color:red}, ~s{var(--a, red)}, ~s{var(a)}, ~s{var(--a")}, "url(x)"] do
        assert Ink.color(bad) == nil
        assert Ink.cast(bad) == {:error, {:invalid_option, :ink}}
      end
    end

    test "HTML takes the variable; a terminal its fallback, or its own ink" do
      {frame, _} = AsciiArt.frame(AsciiArt.new!("dividers", ink: "var(--rule, #336699)"), 0.0)
      assert frame.palette == ["var(--rule, #336699)"]

      html = frame |> HTML.render() |> IO.iodata_to_binary()
      assert html =~ ~s|<span style="color:var(--rule, #336699)">|

      ansi = frame |> ANSI.render() |> IO.iodata_to_binary()
      assert ansi =~ "\e[38;2;51;102;153m"

      {frame, _} = AsciiArt.frame(AsciiArt.new!("dividers", ink: "var(--rule)"), 0.0)
      ansi = frame |> ANSI.render() |> IO.iodata_to_binary()
      assert ansi =~ "\e[39m"
      refute ansi =~ "38;2"
    end
  end

  describe "tint/2" do
    test "one colour is every cell's, the text untouched and no ground behind" do
      plain = %{frame(["ab ", " cd"]) | ground: "#080b12"}
      tinted = Ink.tint(plain, ink!("#ff8800"))
      assert tinted.text == plain.text and tinted.lines == plain.lines
      assert tinted.palette == ["#ff8800"]
      assert tinted.colors == <<0, 0, 0, 0, 0, 0>>
      assert tinted.ground == nil
    end

    test "several run left to right by default, through each in turn" do
      [top, bottom] = frame(["abcde", "fghij"]) |> Ink.tint(ink!("#000000,#ffffff")) |> colours()
      assert top == ["#000000", "#404040", "#808080", "#bfbfbf", "#ffffff"]
      assert bottom == top

      [row] = frame(["abcde"]) |> Ink.tint(ink!("#ff0000,#00ff00,#0000ff")) |> colours()
      assert row == ["#ff0000", "#808000", "#00ff00", "#008080", "#0000ff"]
    end

    test "top to bottom" do
      rows =
        frame(["ab", "cd", "ef"]) |> Ink.tint(ink!("#000000,#ffffff", :vertical)) |> colours()

      assert rows == [["#000000", "#000000"], ["#808080", "#808080"], ["#ffffff", "#ffffff"]]
    end

    test "diagonal runs corner to corner, at 45° on screen however tall a cell is" do
      tall = frame(["abc", "def"]) |> Ink.tint(ink!("#000000,#ffffff", :diagonal)) |> colours()
      assert [["#000000", "#404040", "#808080"], ["#808080", "#bfbfbf", "#ffffff"]] = tall

      square = frame(["ab", "cd", "ef"], 1) |> Ink.tint(ink!("#000000,#ffffff", :diagonal))

      # Thirds, to the nearest of the gradient's 65 steps.
      assert colours(square) == [
               ["#000000", "#545454"],
               ["#545454", "#ababab"],
               ["#ababab", "#ffffff"]
             ]
    end

    test "a single cell or line takes the first colour" do
      assert frame(["a"]) |> Ink.tint(ink!("#000,#fff", :diagonal)) |> colours() == [["#000000"]]

      assert frame(["ab"]) |> Ink.tint(ink!("#000,#fff", :vertical)) |> colours() ==
               [["#000000", "#000000"]]
    end

    test "a gradient is 65 colours at any size, its ends exact, so a player sends it once" do
      ink = ink!("#102030,#f0e0d0")
      wide = frame([String.duplicate("x", 300)]) |> Ink.tint(ink)
      assert length(wide.palette) == 65
      assert hd(wide.palette) == "#102030" and List.last(wide.palette) == "#f0e0d0"
      assert :binary.at(wide.colors, 299) == 64

      narrow = frame(["xyz"]) |> Ink.tint(ink)
      assert narrow.palette == wide.palette
      assert narrow.colors == <<0, 32, 64>>
    end

    test "a frame with colours of its own, or no ink, is left as it is" do
      {coloured, _} = "elixir" |> AsciiArt.new!() |> AsciiArt.frame(0.0)
      assert Ink.tint(coloured, ink!("#ff8800")) == coloured
      plain = frame(["ab"])
      assert Ink.tint(plain, nil) == plain
    end
  end
end
