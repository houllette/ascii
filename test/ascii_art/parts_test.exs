defmodule AsciiArt.PartsTest do
  use ExUnit.Case, async: true

  doctest AsciiArt.Parts

  alias AsciiArt.{Frame, Ink, Parts}
  alias AsciiArt.Kit.Palette

  @meta %AsciiArt.Meta{
    name: "listing",
    category: :ui,
    note: "a listing",
    cols: 6,
    rows: 2,
    fps: 0,
    parts: [{"folder", "#58a6ff"}, {"file", nil}, {"file.md", "#8b949e"}, {"branch", nil}]
  }

  defp frame(lines) do
    %Frame{
      text: Enum.join(lines, "\n"),
      lines: lines,
      cols: String.length(hd(lines)),
      rows: length(lines),
      t: 0.0
    }
  end

  defp ink!(colors, parts) do
    {:ok, ink} = Ink.cast(colors)
    {:ok, parts} = Parts.cast(parts, @meta)
    Ink.put_parts(ink, parts)
  end

  defp colours(%Frame{cols: cols, rows: rows} = frame),
    do: for(y <- 0..(rows - 1), do: for(x <- 0..(cols - 1), do: Frame.color_at(frame, x, y)))

  describe "cast/3 and suggested/2" do
    test "a part's colour can be a CSS variable" do
      assert Parts.cast(%{folder: "var(--dir, #58a6ff)", file: "var(--fg)"}, @meta) ==
               {:ok, %{"folder" => "var(--dir, #58a6ff)", "file" => "var(--fg)"}}
    end

    test "on paper, the suggestions are for a light page" do
      assert Parts.cast(true, @meta, paper: true) ==
               {:ok, %{"folder" => "#0969da", "file.md" => "#6e7781"}}

      assert Parts.cast(true, @meta, paper: false) == Parts.cast(true, @meta)
    end

    test "a colour of no pair is darkened until it reads on white; a dark one is kept" do
      meta = %{@meta | parts: [{"folder", "#e3b341"}, {"file", "#123456"}]}
      %{"folder" => folder, "file" => file} = Parts.suggested(meta, paper: true)
      assert file == "#123456"
      assert folder != "#e3b341"
      {r, g, b} = Palette.rgb255(folder)
      {r0, g0, b0} = Palette.rgb255("#e3b341")
      assert r < r0 and g < g0 and b < b0
    end

    test "parts: true on paper, through new/2" do
      {frame, _} = AsciiArt.frame(AsciiArt.new!("boot-log", parts: true, paper: true), 0.0)
      assert "#1a7f37" in frame.palette
      refute "#3fb950" in frame.palette
    end
  end

  describe "cast/2" do
    test "names, as atoms or strings, to colours" do
      assert Parts.cast(%{"file.md" => "ccc", folder: "#58A6FF"}, @meta) ==
               {:ok, %{"folder" => "#58a6ff", "file.md" => "#cccccc"}}

      assert Parts.cast([folder: "#fff", file: nil], @meta) ==
               {:ok, %{"folder" => "#ffffff", "file" => nil}}

      assert Parts.cast(%{"file" => ""}, @meta) == {:ok, %{"file" => nil}}
    end

    test "true is the colours the piece suggests; nothing is none" do
      assert Parts.cast(true, @meta) == {:ok, %{"folder" => "#58a6ff", "file.md" => "#8b949e"}}
      for none <- [nil, false, %{}, []], do: assert(Parts.cast(none, @meta) == {:ok, %{}})
    end

    test "any name under one the piece lists, even one it never uses" do
      assert {:ok, %{"file.tsx" => "#3178c6"}} = Parts.cast(%{"file.tsx" => "#3178c6"}, @meta)
    end

    test "a name the piece does not list, or a colour that is not one, is refused" do
      assert Parts.cast(%{folders: "#fff"}, @meta) ==
               {:error, {:invalid_option, {:parts, :folders}}}

      assert Parts.cast(%{"Folder!" => "#fff"}, @meta) ==
               {:error, {:invalid_option, {:parts, "Folder!"}}}

      assert Parts.cast(%{folder: "blue"}, @meta) ==
               {:error, {:invalid_option, {:parts, :folder}}}

      assert Parts.cast("folder", @meta) == {:error, {:invalid_option, :parts}}

      assert Parts.cast(%{1 => "#fff"}, @meta) ==
               {:error, {:invalid_option, {:parts, {1, "#fff"}}}}

      many = for i <- 1..65, into: %{}, do: {"file.x#{i}", "#fff"}
      assert Parts.cast(many, @meta) == {:error, {:invalid_option, :parts}}
    end

    test "makes no atom of a name" do
      name = "folder_#{System.unique_integer([:positive])}"
      assert {:error, _} = Parts.cast(%{name => "#fff"}, @meta)
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end

  describe "painting parts" do
    @runs [
      [{"branch", "├─"}, {nil, " "}, {"folder", "a/"}, {nil, "  "}],
      [{"branch", "└─"}, {nil, " "}, {"file.md", "b.md"}]
    ]

    test "parts with colours take them; the rest the renderer's own ink" do
      tinted = Ink.tint(frame(["├─ a/  ", "└─ b.md"]), ink!(nil, %{folder: "#58a6ff"}), @runs)
      assert tinted.palette == [nil, "#58a6ff"]

      assert colours(tinted) == [
               [nil, nil, nil, "#58a6ff", "#58a6ff", nil, nil],
               List.duplicate(nil, 7)
             ]
    end

    test "over an ink, and a name's colour covers the names under it" do
      ink = ink!("#c9d1d9", %{folder: "#58a6ff", file: "#e3b341"})
      tinted = Ink.tint(frame(["├─ a/  ", "└─ b.md"]), ink, @runs)

      assert colours(tinted) == [
               List.duplicate("#c9d1d9", 3) ++ ["#58a6ff", "#58a6ff", "#c9d1d9", "#c9d1d9"],
               List.duplicate("#c9d1d9", 3) ++ List.duplicate("#e3b341", 4)
             ]
    end

    test "the most particular name wins, and nil takes the base" do
      [_, row] =
        Ink.tint(
          frame(["├─ a/  ", "└─ b.md"]),
          ink!("#000", %{file: "#fff", "file.md": "#f00"}),
          @runs
        )
        |> colours()

      assert Enum.drop(row, 3) == List.duplicate("#ff0000", 4)

      [_, row] =
        Ink.tint(
          frame(["├─ a/  ", "└─ b.md"]),
          ink!("#000", %{file: "#fff", "file.md": nil}),
          @runs
        )
        |> colours()

      assert Enum.drop(row, 3) == List.duplicate("#000000", 4)
    end

    test "the palette is the same whatever the frame holds" do
      ink = ink!(nil, %{folder: "#58a6ff", file: "#e3b341"})

      empty =
        Ink.tint(frame(["       ", "       "]), ink, [[{nil, "       "}], [{nil, "       "}]])

      full = Ink.tint(frame(["├─ a/  ", "└─ b.md"]), ink, @runs)
      assert empty.palette == full.palette
    end

    test "a row whose runs do not make it up keeps the base" do
      runs = [[{"folder", "├─"}], [{"folder", "└─ b.md and more"}]]
      tinted = Ink.tint(frame(["├─ a/  ", "└─ b.md"]), ink!(nil, %{folder: "#fff"}), runs)
      assert tinted.colors == :binary.copy(<<0>>, 14)
    end
  end

  describe "with a piece" do
    test "a file tree's folders in one colour, its files by type" do
      anim = AsciiArt.new!("file-tree", parts: %{folder: "#58a6ff", "file.md": "#d29922"})
      {frame, _} = AsciiArt.frame(anim, 3.0)
      assert frame.text == AsciiArt.render!("file-tree", 3.0)
      assert frame.palette == [nil, "#58a6ff", "#d29922"]

      at = fn word ->
        {y, line} =
          frame.lines
          |> Enum.with_index()
          |> Enum.find_value(fn {l, y} -> if l =~ word, do: {y, l} end)

        x =
          line |> :binary.match(word) |> elem(0) |> then(&String.length(binary_part(line, 0, &1)))

        Frame.color_at(frame, x, y)
      end

      assert at.("docs/") == "#58a6ff"
      assert at.("guide.md") == "#d29922"
      assert at.("favicon.ico") == nil
      assert at.("├──") == nil
    end

    test "a boot log's statuses as the piece suggests" do
      {frame, _} = "boot-log" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)
      ok = Enum.find_index(frame.lines, &(&1 =~ "[  OK  ]"))
      warn = Enum.find_index(frame.lines, &(&1 =~ "[ WARN ]"))
      assert Frame.color_at(frame, 2, ok) == "#3fb950"
      assert Frame.color_at(frame, 2, warn) == "#d29922"
      assert Frame.color_at(frame, 12, ok) == nil
    end

    test "parts take the still as kept, and play over an ink" do
      {:ok, still} = AsciiArt.still("file-tree", ink: "#c9d1d9", parts: %{folder: "#58a6ff"})
      assert still.palette == ["#c9d1d9", "#58a6ff"]
      assert {:ok, %Frame{colors: nil}} = AsciiArt.still("file-tree")
    end

    test "a piece without parts takes none" do
      assert AsciiArt.new("donut", parts: %{shade: "#fff"}) ==
               {:error, {:invalid_option, {:parts, :shade}}}

      {frame, _} = "donut" |> AsciiArt.new!(parts: true) |> AsciiArt.frame(0.0)
      assert frame.colors == nil
    end
  end

  describe "renderers" do
    alias AsciiArt.Render.{ANSI, HTML}

    setup do
      {frame, _} =
        "file-tree" |> AsciiArt.new!(parts: %{folder: "#58a6ff"}) |> AsciiArt.frame(3.0)

      %{frame: frame}
    end

    test "ANSI writes the rest in the terminal's own foreground", %{frame: frame} do
      out = frame |> ANSI.render() |> IO.iodata_to_binary()
      assert out =~ "\e[38;2;88;166;255mdocs/"
      assert out =~ "\e[39m"
    end

    test "HTML leaves the rest as plain text", %{frame: frame} do
      html = frame |> HTML.render() |> IO.iodata_to_binary()
      assert html =~ ~s(<span style="color:#58a6ff">docs/)
      refute html =~ ~s(color:")
      assert html =~ "guide.md"
    end
  end
end
