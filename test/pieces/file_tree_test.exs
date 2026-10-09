defmodule AsciiArt.Pieces.FileTreeTest do
  use ExUnit.Case, async: true

  alias AsciiArt.Pieces.FileTree

  @all ["docs/", "public/", "src/", "src/components/", "src/lib/", "tests/"]
  @app ["lib/app.ex", "lib/app/repo.ex", "mix.exs", "README.md", "test/"]

  use AsciiArt.ContractCase,
    piece: AsciiArt.Pieces.FileTree,
    variants: [
      %{walk: false, open: ["src/", "src/lib/"], cursor: "src/lib/fetch.ts"},
      %{walk: false, open: @all, cursor: "src/index.ts", rows: 7},
      %{walk: false, open: @all, cursor: "README.md", cols: 20, rows: 9},
      %{walk: false, paths: @app, open: ["lib/"], cursor: "lib/app/", root: "app"},
      %{walk: false},
      %{walk: false, entries: "", root: "empty"},
      %{cols: 50, rows: 30},
      %{cols: 20, rows: 10},
      %{paths: @app, root: "app"}
    ]

  use AsciiArt.GoldenCase, slug: "file-tree", piece: AsciiArt.Pieces.FileTree

  doctest AsciiArt.Pieces.FileTree

  defp lines(options, t \\ 0.0) do
    {frame, _} = "file-tree" |> AsciiArt.new!(options: options) |> AsciiArt.frame(t)
    Enum.map(frame.lines, &String.trim_trailing/1)
  end

  defp still(options), do: Map.merge(%{walk: false}, Map.new(options))

  # The options after each event in turn, from these; every event used.
  defp events(options, events) do
    Enum.reduce(events, Map.merge(AsciiArt.meta!("file-tree").options, still(options)), fn
      event, options ->
        case FileTree.handle_event(event, options) do
          {:ok, options} -> options
          :ignore -> flunk("#{inspect(event)} ignored at #{inspect(options)}")
        end
    end)
  end

  defp options(options), do: Map.merge(AsciiArt.meta!("file-tree").options, still(options))

  describe "walk: false" do
    test "the tree stands as open and cursor say, the cursor the branch turned arrow" do
      assert lines(still(open: ["src/", "src/lib/"], cursor: "src/lib/fetch.ts"))
             |> Enum.take(14) == [
               "      .",
               "      ├── docs/ +",
               "      ├── public/ +",
               "      ├── src/",
               "      │   ├── components/ +",
               "      │   ├── lib/",
               "      │   │   ├─> fetch.ts",
               "      │   │   └── format.ts",
               "      │   ├── index.ts",
               "      │   └── styles.css",
               "      ├── tests/ +",
               "      ├── package.json",
               "      └── README.md",
               ""
             ]

      assert List.last(lines(still(open: ["src/"]))) == "      6 directories, 14 files"
    end

    test "it never moves" do
      options = still(open: ["src/"], cursor: "src/index.ts")
      assert lines(options, 0.0) == lines(options, 7.3)
    end

    test "a cursor inside a closed folder sits on the nearest folder shown" do
      assert "      ├─> src/ +" in lines(still(cursor: "src/lib/fetch.ts"))
      assert "      │   ├─> lib/ +" in lines(still(open: ["src/"], cursor: "src/lib/fetch.ts"))
    end

    test "no cursor, or one not in the tree, draws none" do
      for cursor <- ["", "nowhere.txt", "src"] do
        refute lines(still(cursor: cursor)) |> Enum.join() |> String.contains?(">")
      end
    end

    test "a folder open inside a closed one stays closed until that one opens" do
      refute "      │   │   ├── fetch.ts" in lines(still(open: ["src/lib/"]))
    end

    test "a listing longer than its rows keeps the cursor in the middle" do
      options = still(open: @all, rows: 8)

      assert lines(Map.put(options, :cursor, "docs/guide.md")) == [
               "      .",
               "      ├── docs/",
               "      │   ├─> guide.md",
               "      │   └── notes.md",
               "      ├── public/",
               "      │   ├── favicon.ico",
               "",
               "      6 directories, 14 files"
             ]

      assert lines(Map.put(options, :cursor, "src/lib/fetch.ts")) == [
               "      .",
               "      │   │   └── menu.ts",
               "      │   ├── lib/",
               "      │   │   ├─> fetch.ts",
               "      │   │   └── format.ts",
               "      │   ├── index.ts",
               "",
               "      6 directories, 14 files"
             ]

      assert lines(Map.put(options, :cursor, "README.md")) |> Enum.slice(1, 5) == [
               "      │   └── styles.css",
               "      ├── tests/",
               "      │   └── format.test.ts",
               "      ├── package.json",
               "      └─> README.md"
             ]
    end
  end

  describe "keys and clicks" do
    test "up and down move the cursor, home, end and the pages too" do
      assert events([], [{:key, "down"}]).cursor == "docs/"
      assert events([], [{:key, "end"}]).cursor == "README.md"
      assert events([cursor: "docs/"], [{:key, "down"}, {:key, "down"}]).cursor == "src/"
      assert events([cursor: "src/"], [{:key, "up"}]).cursor == "public/"
      assert events([cursor: "src/"], [{:key, "home"}]).cursor == "docs/"
      assert events([cursor: "src/"], [{:key, "end"}]).cursor == "README.md"

      # Five rows of entries a page, in eight rows.
      paged = [open: @all, rows: 8]

      assert events([cursor: "docs/"] ++ paged, [{:key, "page_down"}]).cursor ==
               "public/robots.txt"

      assert events([cursor: "README.md"] ++ paged, [{:key, "page_up"}]).cursor == "src/index.ts"
      assert events([cursor: "tests/"] ++ paged, [{:key, "page_down"}]).cursor == "README.md"
    end

    test "nothing to move to is ignored" do
      assert FileTree.handle_event({:key, "up"}, options(cursor: "docs/")) == :ignore
      assert FileTree.handle_event({:key, "down"}, options(cursor: "README.md")) == :ignore
    end

    test "→ and enter open a folder, → moves into an open one, ← closes it" do
      assert events([cursor: "src/"], [{:key, "right"}]).open == ["src/"]
      assert events([cursor: "src/"], [{:key, "enter"}]).open == ["src/"]

      inside = events([cursor: "src/"], [{:key, "right"}, {:key, "right"}])
      assert inside.cursor == "src/components/"

      assert events([open: ["docs/", "src/"], cursor: "src/"], [{:key, "left"}]) ==
               options(open: ["docs/"], cursor: "src/")
    end

    test "← on an entry moves to its folder; at the top it is ignored" do
      options = [open: ["src/", "src/lib/"], cursor: "src/lib/fetch.ts"]
      assert events(options, [{:key, "left"}]).cursor == "src/lib/"
      assert FileTree.handle_event({:key, "left"}, options(cursor: "package.json")) == :ignore
    end

    test "space opens and closes a folder; enter on a file is the app's" do
      assert events([cursor: "tests/"], [{:key, " "}]).open == ["tests/"]
      assert events([open: ["tests/"], cursor: "tests/"], [{:key, " "}]).open == []

      assert FileTree.handle_event({:key, "enter"}, options(cursor: "README.md")) == :ignore
      assert FileTree.handle_event({:key, " "}, options(cursor: "README.md")) == :ignore
    end

    test "a folder opened or closed takes the cursor where it is shown" do
      assert events([cursor: "src/lib/fetch.ts"], [{:key, "enter"}]) ==
               options(open: ["src/"], cursor: "src/")
    end

    test "keys move the cursor that is shown" do
      # On src/, where src/index.ts inside it is drawn.
      assert events([cursor: "src/index.ts"], [{:key, "down"}]).cursor == "tests/"
    end

    test "a click on an entry's row puts the cursor on it, and opens or closes a folder" do
      assert events([], [{:click, 10, 6}]) == options(cursor: "README.md")
      assert events([], [{:click, 0, 3}]) == options(open: ["src/"], cursor: "src/")
      assert events([open: ["src/"]], [{:click, 30, 3}]) == options(open: [], cursor: "src/")
    end

    test "a click on the root, the count, a blank row or past the frame is ignored" do
      for {x, y} <- [{6, 0}, {6, 22}, {6, 15}, {36, 3}, {6, 23}] do
        assert FileTree.handle_event({:click, x, y}, options([])) == :ignore
      end
    end

    test "a click lands on the row as scrolled" do
      options = options(open: @all, rows: 8, cursor: "src/lib/fetch.ts")
      assert {:ok, %{cursor: "src/index.ts"}} = FileTree.handle_event({:click, 8, 5}, options)
    end

    test "the walk takes no events" do
      for event <- [{:key, "down"}, {:click, 8, 3}] do
        assert FileTree.handle_event(event, AsciiArt.meta!("file-tree").options) == :ignore
      end
    end

    test "the open folders never grow past what the options take" do
      open = for i <- 1..256, do: "f#{i}/"
      paths = for i <- 0..256, do: "f#{i}/x"
      options = options(paths: paths, open: open, cursor: "f0/")
      {:ok, %{open: opened}} = FileTree.handle_event({:key, " "}, options)
      assert length(opened) == 256
      assert List.first(opened) == "f2/" and List.last(opened) == "f0/"
    end

    test "through the animation, the frame follows" do
      anim = AsciiArt.new!("file-tree", options: %{walk: false})
      {:ok, anim} = AsciiArt.handle_event(anim, {:key, "down"})
      {:ok, anim} = AsciiArt.handle_event(anim, {:key, "enter"})
      {frame, _} = AsciiArt.frame(anim, 0.0)
      assert anim.options.cursor == "docs/"
      assert Enum.at(frame.lines, 1) |> String.trim_trailing() == "      ├─> docs/"
      assert Enum.at(frame.lines, 2) |> String.trim_trailing() == "      │   ├── guide.md"
    end
  end

  describe "entries/1 and paths" do
    test "folders made from the paths, entries in the order first given" do
      assert FileTree.entries(["b/z.ex", "a.ex", "b/y.ex", "c/", "b/d/e.ex"]) ==
               Enum.join(["b/", "  z.ex", "  y.ex", "  d/", "    e.ex", "a.ex", "c/"], "\n")
    end

    test "a path holding others is a folder, whether it came first or not" do
      assert FileTree.entries(["lib", "lib/a.ex"]) == "lib/\n  a.ex"
      assert FileTree.entries(["lib/a.ex", "lib"]) == "lib/\n  a.ex"
    end

    test "empty names, `.` and line breaks are left out" do
      assert FileTree.entries(["./lib//a.ex", "/", "", "b\nc.ex"]) == "lib/\n  a.ex\nb c.ex"
    end

    test "paths draw the tree entries/1 gives" do
      options = %{root: "app", walk: false, open: ["lib/", "lib/app/"], cursor: "lib/app/repo.ex"}

      assert lines(Map.put(options, :paths, @app)) ==
               lines(Map.put(options, :entries, FileTree.entries(@app)))

      assert lines(Map.put(options, :paths, @app)) |> Enum.take(8) == [
               "       app",
               "       ├── lib/",
               "       │   ├── app.ex",
               "       │   └── app/",
               "       │       └─> repo.ex",
               "       ├── mix.exs",
               "       ├── README.md",
               "       └── test/"
             ]
    end
  end

  describe "cols and rows" do
    test "the size the options give, the listing centred in its width" do
      anim = AsciiArt.new!("file-tree", options: %{cols: 50, rows: 30})
      {frame, _} = AsciiArt.frame(anim, 0.0)
      assert {frame.cols, frame.rows} == {50, 30}
      assert frame.lines |> Enum.at(0) |> String.trim_trailing() == "             ."
      assert frame.lines |> List.last() |> String.trim_trailing() =~ ~r/^ {13}6 directories/
    end

    test "too narrow, lines are cut at the edge" do
      lines = lines(still(open: ["src/", "src/components/"], cols: 14))
      assert "├── src/" in lines
      assert "│   ├── compon" in lines
    end
  end

  describe "describe/1" do
    test "the root, the counts and the cursor's path" do
      options = options(open: ["src/"], cursor: "src/index.ts", root: "web")

      assert FileTree.describe(options) ==
               "file tree of web: 6 folders, 14 files; at src/index.ts"

      assert AsciiArt.new!("file-tree", options: %{walk: false, paths: ["a.ex"], root: ""})
             |> AsciiArt.describe() == "file tree: 0 folders, 1 file"
    end

    test "nothing of its own on the walk" do
      assert FileTree.describe(AsciiArt.meta!("file-tree").options) == nil
    end
  end

  describe "parts" do
    defp parts(options) do
      {frame, anim} = "file-tree" |> AsciiArt.new!(options: options) |> AsciiArt.frame(0.0)
      FileTree.parts(frame, anim.options)
    end

    test "a still tree's cursor row, its branches, names and markers" do
      rows = parts(still(open: ["src/", "src/lib/"], cursor: "src/lib/fetch.ts"))

      assert Enum.at(rows, 6) == [
               {nil, "      "},
               {"branch", "│   │   "},
               {"cursor", "├─>"},
               {nil, " "},
               {"file.ts", "fetch.ts"},
               {nil, String.duplicate(" ", 10)}
             ]

      assert [_, {"branch", "├──"}, _, {"folder", "docs/"}, {"marker", " +"}, _] =
               Enum.at(rows, 1)
    end

    test "scrolled rows label as any other" do
      rows = parts(still(open: @all, rows: 8, cursor: "src/lib/fetch.ts"))

      assert Enum.at(rows, 1) == [
               {nil, "      "},
               {"branch", "│   │   └──"},
               {nil, " "},
               {"file.ts", "menu.ts"},
               {nil, String.duplicate(" ", 11)}
             ]

      assert [{"summary", "6 directories, 14 files"} | _] = rows |> List.last() |> tl()
    end
  end
end
