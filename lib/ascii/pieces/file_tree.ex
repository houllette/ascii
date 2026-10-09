defmodule Ascii.Pieces.FileTree do
  @moduledoc """
  A tree listing opened folder by folder, then closed again.

  A project listed the way `tree -F` prints it. As upstream draws it, a
  cursor walks down the list opening one folder at a time, then closes them
  from the bottom up. With `walk: false` it is a tree to use instead: your
  files, the folders you open, and a cursor that keys and clicks move, in a
  terminal UI or a LiveView.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): the tree
  is laid out anew from them.

    * `root` - the first line, above the listing. Default `"."`.
    * `entries` - the listing as text: one entry a line, two spaces of
      indent a level, folders ending in "/". Default: upstream's small web
      project. Being text, it is cut at 256 characters: for a real tree,
      give `paths`.
    * `paths` - the entries as a list of paths, as `Path.wildcard/1` gives
      them, in place of `entries`: each path's folders are made from it, a
      path ending in "/" is a folder, and every folder's entries come in the
      order first given (sort them for `tree`'s order). Up to 256 paths.
      Default `[]`, for `entries`. `entries/1` gives the text for paths.
    * `walk` - `true` (the default) plays upstream's walk; `false` draws the
      tree still, as `open` and `cursor` say, and takes keys and clicks.
    * `open` - with `walk: false`, the paths of the open folders, as
      `["src/", "src/lib/"]`. An entry's path is its name after its
      folders', `"src/lib/fetch.ts"`, a folder's ending in "/". Default `[]`:
      only the root's entries show.
    * `cursor` - with `walk: false`, the path of the entry under the cursor,
      drawn as the walk draws it, the branch turned arrow. One inside a
      closed folder sits on the nearest folder shown; `""` (the default), or
      a path not in the tree, is no cursor. A listing longer than its rows
      scrolls to keep the cursor in the middle of them.
    * `cols`, `rows` - the frame's size, 12 to 200 by 4 to 100; 36 by 23 by
      default. The listing is centred in the width, between the root and a
      blank row over the count.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `root` - the first line.
    * `branch` - the tree's lines, grey.
    * `cursor` - the branch turned arrow, yellow.
    * `folder` - a folder's name, blue.
    * `file`, and `file.<extension>` - a file's name, and by its extension
      in lowercase (`file.ts` for `index.ts`; a name without one, or a
      dotfile, is just `file`). Suggested: `file.ex` and `file.exs` purple,
      `file.ts` blue, `file.js` and `file.json` yellow, `file.css` pink,
      `file.md` grey; any other in the ink. `%{"file.rs" => "#dea584"}`
      colours a kind of your own.
    * `marker` - the `+` on a closed folder, yellow.
    * `summary` - the count on the last row, grey.

  ## Keys and clicks

  With `walk: false`, `Ascii.handle_event/2` takes keys and clicks,
  changing `cursor` and `open`, from which the app reads the choice:

    * ↑ and ↓ move the cursor, as do home, end, page up and page down;
      with no cursor, any of them puts it on the first entry (end, the
      last).
    * → or enter opens a closed folder, and → on an open one moves into it;
      ← closes an open folder, or moves to the folder an entry is in; enter
      and space open and close a folder.
    * A click on an entry's row puts the cursor on it, and opens or closes
      it if it is a folder.
    * Enter on a file is ignored, as is a key that would change nothing:
      the app has the key, and the file in `cursor`.

  Walking, it takes none. In Phoenix, give the player `interactive` (and
  `notify` to be told of each key and click); in ExRatatui,
  `Ascii.ExRatatui.handle_event/3`; in a terminal,
  `mix ascii.play file-tree --option walk=false --interactive`.

  ## Screen readers

  `Ascii.describe/1` tells the tree and where the cursor is, as "file
  tree of my_app: 2 folders, 4 files; at lib/my_app.ex". Walking, it gives
  the piece's name and note.

  ## Example

  ```elixir
  paths = ["lib/my_app.ex", "lib/my_app/repo.ex", "mix.exs", "README.md"]
  options = %{walk: false, paths: paths, root: "my_app", open: ["lib/"], cursor: "lib/"}
  tree = Ascii.new!("file-tree", options: options, parts: true)

  {:ok, tree} = Ascii.handle_event(tree, {:key, "down"})
  tree.options.cursor
  #=> "lib/my_app.ex"

  Ascii.describe(tree)
  #=> "file tree of my_app: 2 folders, 4 files; at lib/my_app.ex"
  ```

  ```heex
  <Ascii.Phoenix.live_player id="files" piece="file-tree" options={%{walk: false, paths: @paths}} parts interactive notify />
  ```

  Ported from `src/pieces/file-tree.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{JSMath, Parts}
  alias Ascii.Kit.Text

  @entries Enum.join(
             [
               "docs/",
               "  guide.md",
               "  notes.md",
               "public/",
               "  favicon.ico",
               "  robots.txt",
               "src/",
               "  components/",
               "    button.ts",
               "    card.ts",
               "    menu.ts",
               "  lib/",
               "    fetch.ts",
               "    format.ts",
               "  index.ts",
               "  styles.css",
               "tests/",
               "  format.test.ts",
               "package.json",
               "README.md"
             ],
             "\n"
           )

  @meta %Ascii.Meta{
    name: "file tree",
    category: :ui,
    note: "a tree listing opened folder by folder, then closed again",
    cols: 36,
    rows: 23,
    fps: 15,
    options: %{
      root: ".",
      entries: @entries,
      paths: [],
      walk: true,
      open: [],
      cursor: "",
      cols: 36,
      rows: 23
    },
    bounds: %{cols: {12, 200}, rows: {4, 100}},
    parts: [
      {"root", nil},
      {"branch", "#8b949e"},
      {"cursor", "#d29922"},
      {"folder", "#58a6ff"},
      {"file", nil},
      {"file.ex", "#a371f7"},
      {"file.exs", "#a371f7"},
      {"file.ts", "#3b8eea"},
      {"file.js", "#e3b341"},
      {"file.json", "#e3b341"},
      {"file.css", "#db61a2"},
      {"file.md", "#8b949e"},
      {"marker", "#d29922"},
      {"summary", "#8b949e"}
    ]
  }

  # Seconds per line the cursor steps; on a folder before it opens or closes;
  # per line appearing or going; all open; all closed, held at both ends of
  # the loop.
  @move 0.13
  @pause 0.3
  @reveal 0.07
  @hold 1.8
  @rest 0.7

  # What JS's String.prototype.trim removes: WhiteSpace and LineTerminator.
  @js_space [
              0x09,
              0x0A,
              0x0B,
              0x0C,
              0x0D,
              0x20,
              0xA0,
              0x1680,
              0x2028,
              0x2029,
              0x202F,
              0x205F,
              0x3000,
              0xFEFF
            ] ++ Enum.to_list(0x2000..0x200A)

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{cols: cols, rows: rows}), do: {trunc(cols), trunc(rows)}

  @impl true
  def init(%{walk: true} = options) do
    %{tree: tree, dirs: dirs, view: view} = layout(options)

    cursor =
      case {dirs, tree[:root].kids} do
        {[first | _], _} -> first
        {[], [first | _]} -> first
        {[], []} -> nil
      end

    b = %{
      view: view,
      shown: %{root: length(tree[:root].kids)},
      cursor: cursor,
      snaps: [],
      total: 0,
      start: 0
    }

    b = snap(b, @rest)
    n = length(dirs)
    goal = JSMath.ceil(n * 0.6)

    b =
      dirs
      |> Enum.with_index(1)
      |> Enum.reduce(b, fn {node, i}, b ->
        b = b |> walk_to(node) |> snap(@pause)
        count = length(tree[node].kids)
        b = Enum.reduce(1..count//1, b, fn k, b -> b |> show(node, k) |> snap(@reveal) end)
        if i == goal, do: %{b | start: b.total}, else: b
      end)

    b = snap(b, @hold)

    b =
      dirs
      |> Enum.reverse()
      |> Enum.reduce(b, fn node, b ->
        b = b |> walk_to(node) |> snap(@pause)
        count = length(tree[node].kids)
        Enum.reduce((count - 1)..0//-1, b, fn k, b -> b |> show(node, k) |> snap(@reveal) end)
      end)

    # The last picture is the first one, so the loop closes on it.
    %{snaps: b.snaps |> Enum.reverse() |> List.to_tuple(), total: b.total + @rest, start: b.start}
  end

  # This port's own: the tree as the options say, which never moves.
  def init(options) do
    layout = layout(options)
    %{listing: listing, top: top} = still(layout, options)
    view = layout.view
    shown = for {_, text} <- Enum.slice(listing, top, rows_shown(view)), do: text
    %{picture: view |> lines(shown) |> Enum.intersperse(?\n) |> IO.iodata_to_binary()}
  end

  # The tree, its folders that hold something in order, and how it is laid
  # out: what upstream's init works out, at the options' size.
  defp layout(%{root: label} = options) do
    {cols, rows} = size(options)
    tree = parse(source(options))
    {dirs, nd, nf} = collect(tree, :root, {[], 0, 0})
    dirs = Enum.reverse(dirs)

    # Counted over the whole tree, as tree itself does, not just what is open.
    summary =
      "#{nd} director#{if nd == 1, do: "y", else: "ies"}, #{nf} file#{if nf == 1, do: "", else: "s"}"

    # Centre the listing as it stands fully open, with room for the marker.
    open = Map.new(dirs, &{&1, length(tree[&1].kids)})
    shown = Map.put(open, :root, length(tree[:root].kids))
    lengths = for {_, text} <- listing(tree, shown, nil), do: Text.length(text) + 2
    width = Enum.max([Text.length(label), Text.length(summary) | lengths])
    pad = String.duplicate(" ", max(0, floor((cols - width) / 2)))

    view = %{tree: tree, label: label, summary: summary, pad: pad, cols: cols, rows: rows}
    %{tree: tree, dirs: dirs, folders: nd, files: nf, view: view}
  end

  defp source(%{paths: [], entries: entries}), do: entries
  defp source(%{paths: paths}), do: entries(paths)

  # A folder for entries/1: its names in order, the folders among them, and
  # what each folder holds.
  @folder %{names: [], sub: %{}, dirs: MapSet.new()}

  @doc """
  `entries` text for a list of paths, as the `paths` option takes them: each
  path's folders are made from it, a path ending in "/" (or holding others)
  is a folder, and every folder's entries come in the order first given.

      iex> Ascii.Pieces.FileTree.entries(["lib/app.ex", "lib/app/repo.ex", "mix.exs", "priv/"])
      "lib/\\n  app.ex\\n  app/\\n    repo.ex\\nmix.exs\\npriv/"
  """
  @spec entries(paths :: [String.t()]) :: String.t()
  def entries(paths) when is_list(paths) do
    paths
    |> Enum.reduce(@folder, fn path, top ->
      case names(path) do
        {[], _dir?} -> top
        {names, dir?} -> put_path(top, names, dir?)
      end
    end)
    |> entry_lines("")
    |> Enum.join("\n")
  end

  # A path's names, without empty ones, `.`, or line breaks; and whether it
  # ends in a folder.
  defp names(path) do
    names =
      for name <- String.split(path, "/"),
          name = name |> String.replace(["\n", "\r"], " ") |> String.trim(),
          name not in ["", "."],
          do: name

    {names, String.ends_with?(String.trim_trailing(path), "/")}
  end

  defp put_path(folder, [name], dir?) do
    folder = add_name(folder, name)
    if dir?, do: %{folder | dirs: MapSet.put(folder.dirs, name)}, else: folder
  end

  defp put_path(folder, [name | rest], dir?) do
    folder = add_name(folder, name)
    sub = put_path(Map.get(folder.sub, name, @folder), rest, dir?)
    %{folder | sub: Map.put(folder.sub, name, sub), dirs: MapSet.put(folder.dirs, name)}
  end

  defp add_name(%{names: names} = folder, name) do
    if Map.has_key?(folder.sub, name) or MapSet.member?(folder.dirs, name) or name in names,
      do: folder,
      else: %{folder | names: names ++ [name]}
  end

  defp entry_lines(%{names: names, sub: sub, dirs: dirs}, indent) do
    Enum.flat_map(names, fn name ->
      if MapSet.member?(dirs, name),
        do: [indent <> name <> "/" | entry_lines(Map.get(sub, name, @folder), indent <> "  ")],
        else: [indent <> name]
    end)
  end

  # One entry per line, two spaces of indent per level, folders end in "/".
  # Entries are numbered in order; the tree maps each to its name, whether it
  # is a folder, and the entries it holds.
  defp parse(text) do
    {tree, _, _} =
      text
      |> String.split("\n")
      |> Enum.reduce({%{root: %{kids: []}}, [:root], 0}, fn raw, {tree, stack, id} ->
        name = js_trim(raw)

        if name == "" do
          {tree, stack, id}
        else
          depth = div(Text.length(raw) - Text.length(js_trim_start(raw)), 2)
          dir = String.ends_with?(name, "/")
          stack = Enum.take(stack, depth + 1)
          parent = List.last(stack)
          tree = tree |> Map.put(id, %{name: name, dir: dir, kids: []}) |> add_kid(parent, id)
          {tree, if(dir, do: stack ++ [id], else: stack), id + 1}
        end
      end)

    Map.new(tree, fn {id, node} -> {id, %{node | kids: Enum.reverse(node.kids)}} end)
  end

  defp add_kid(tree, parent, id), do: update_in(tree[parent].kids, &[id | &1])

  defp js_trim(s), do: s |> js_trim_start() |> js_trim_end()

  defp js_trim_start(<<c::utf8, rest::binary>>) when c in @js_space, do: js_trim_start(rest)
  defp js_trim_start(s), do: s

  defp js_trim_end(s) do
    s
    |> String.to_charlist()
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 in @js_space))
    |> Enum.reverse()
    |> List.to_string()
  end

  # Folders that hold something, in order, and the folder and file counts.
  defp collect(tree, node, acc) do
    Enum.reduce(tree[node].kids, acc, fn k, {dirs, nd, nf} ->
      %{dir: dir, kids: kids} = tree[k]
      acc = if dir, do: {dirs, nd + 1, nf}, else: {dirs, nd, nf + 1}
      acc = if dir and kids != [], do: put_elem(acc, 0, [k | elem(acc, 0)]), else: acc
      collect(tree, k, acc)
    end)
  end

  # The lines on screen: the folders' entries in order, cut short where a
  # folder is closed or still opening. A closed folder that holds something
  # wears a "+", and the cursor is the branch turning into an arrow.
  defp listing(tree, shown, cursor) do
    tree |> walk(shown, cursor, :root, "", []) |> Enum.reverse()
  end

  defp walk(tree, shown, cursor, node, prefix, out) do
    kids = tree[node].kids
    n = Map.get(shown, node, 0)
    last_i = length(kids) - 1

    kids
    |> Enum.take(n)
    |> Enum.with_index()
    |> Enum.reduce(out, fn {kid, i}, out ->
      %{name: name, dir: dir, kids: grand} = tree[kid]
      last = i == last_i
      branch = if(last, do: "└─", else: "├─") <> if(kid == cursor, do: "> ", else: "─ ")
      closed = dir and grand != [] and Map.get(shown, kid, 0) == 0
      out = [{kid, prefix <> branch <> name <> if(closed, do: " +", else: "")} | out]

      if dir,
        do: walk(tree, shown, cursor, kid, prefix <> if(last, do: "    ", else: "│   "), out),
        else: out
    end)
  end

  # The tree grows down from the top; the count stays on the last row.
  defp render(%{view: view, shown: shown, cursor: cursor}) do
    texts = for {_, text} <- listing(view.tree, shown, cursor), do: text
    view |> lines(texts) |> Enum.intersperse(?\n) |> IO.iodata_to_binary()
  end

  defp lines(%{cols: cols, rows: rows, label: label, summary: summary, pad: pad}, texts) do
    lines = Enum.take([label | texts], rows - 2)
    lines = lines ++ List.duplicate("", rows - 1 - length(lines)) ++ [summary]
    Enum.map(lines, &((pad <> &1) |> Text.pad_end(cols) |> Text.slice(0, cols)))
  end

  # The entries a still tree shows: the rows between the root and the blank
  # row over the count.
  defp rows_shown(%{rows: rows}), do: rows - 3

  # The whole loop as a list of pictures and how long each stays up.
  defp snap(b, dur), do: %{b | snaps: [{b.total, render(b)} | b.snaps], total: b.total + dur}

  defp show(b, node, k), do: %{b | shown: Map.put(b.shown, node, k)}

  defp step(b, dir) do
    vis = listing(b.view.tree, b.shown, b.cursor)
    i = Enum.find_index(vis, &(elem(&1, 0) == b.cursor)) || -1
    # Off either end of the listing upstream throws; the walk never gets there.
    {node, _} = if i + dir >= 0, do: Enum.at(vis, i + dir)
    snap(%{b | cursor: node}, @move)
  end

  defp walk_to(%{cursor: node} = b, node), do: b

  defp walk_to(b, node) do
    vis = listing(b.view.tree, b.shown, b.cursor)
    at = fn n -> Enum.find_index(vis, &(elem(&1, 0) == n)) || -1 end
    dir = if at.(node) > at.(b.cursor), do: 1, else: -1
    walk_steps(b, node, dir)
  end

  defp walk_steps(%{cursor: node} = b, node, _dir), do: b
  defp walk_steps(b, node, dir), do: b |> step(dir) |> walk_steps(node, dir)

  @impl true
  def frame(%{picture: picture} = state, _t, _env), do: {picture, nil, state}

  def frame(%{snaps: snaps, total: total, start: start} = state, t, _env) do
    p = JSMath.mod(t + start, total)
    {state_text(snaps, p, 0), nil, state}
  end

  defp state_text(snaps, p, i) do
    if i + 1 < tuple_size(snaps) and elem(elem(snaps, i + 1), 0) <= p,
      do: state_text(snaps, p, i + 1),
      else: elem(elem(snaps, i), 1)
  end

  # This port's own: the tree as `open` and `cursor` say. The entries
  # shown, by id; the one the cursor is on (or the nearest folder shown
  # holding it), where it is among them, and the first shown on screen, the
  # cursor in the middle where the listing is longer than the rows.
  defp still(%{tree: tree, view: view}, %{open: open, cursor: cursor}) do
    {paths, parents} = paths(tree, :root, "", {%{}, %{}})
    opened = MapSet.new(open)

    shown =
      for {id, %{dir: true, kids: kids}} <- tree,
          MapSet.member?(opened, paths[id]),
          into: %{root: length(tree[:root].kids)},
          do: {id, length(kids)}

    plain = listing(tree, shown, nil)
    ids = Enum.map(plain, &elem(&1, 0))
    at = for({id, ^cursor} <- paths, do: id) |> Enum.min(fn -> nil end)
    at = shown_at(at, MapSet.new(ids), parents)
    index = at && Enum.find_index(ids, &(&1 == at))
    page = rows_shown(view)
    top = if index, do: (index - div(page, 2)) |> min(length(ids) - page) |> max(0), else: 0

    %{
      tree: tree,
      shown: shown,
      listing: if(at, do: listing(tree, shown, at), else: plain),
      ids: ids,
      cursor: at,
      index: index,
      top: top,
      paths: paths,
      parents: parents,
      open: open
    }
  end

  # Each entry's path, its name after its folders' (theirs end in "/"), and
  # the folder it is in.
  defp paths(tree, node, prefix, acc) do
    Enum.reduce(tree[node].kids, acc, fn kid, {paths, parents} ->
      path = prefix <> tree[kid].name
      paths(tree, kid, path, {Map.put(paths, kid, path), Map.put(parents, kid, node)})
    end)
  end

  defp shown_at(nil, _shown, _parents), do: nil
  defp shown_at(:root, _shown, _parents), do: nil

  defp shown_at(id, shown, parents),
    do: if(MapSet.member?(shown, id), do: id, else: shown_at(parents[id], shown, parents))

  @moves ~w(up down home end page_up page_down)

  @impl true
  def handle_event(_event, %{walk: true}), do: :ignore

  def handle_event(event, options) do
    layout = layout(options)

    case act(event, still(layout, options), layout.view) do
      nil ->
        :ignore

      {cursor, open} ->
        new = %{options | cursor: cursor, open: open}
        if new == options, do: :ignore, else: {:ok, new}
    end
  end

  # What an event does to a still tree: the cursor's path and the open
  # folders after it, or nil.
  defp act(_event, %{ids: []}, _view), do: nil

  defp act({:key, key}, %{index: nil, ids: ids} = s, _view) when key in @moves,
    do: to(s, if(key == "end", do: length(ids) - 1, else: 0))

  defp act({:key, key}, %{index: i, ids: ids} = s, view) when key in @moves do
    page = rows_shown(view)

    j =
      case key do
        "up" -> i - 1
        "down" -> i + 1
        "home" -> 0
        "end" -> length(ids) - 1
        "page_up" -> i - page
        "page_down" -> i + page
      end

    to(s, j |> min(length(ids) - 1) |> max(0))
  end

  defp act({:key, _key}, %{cursor: nil}, _view), do: nil

  defp act({:key, "right"}, %{cursor: id, index: i} = s, _view) do
    cond do
      not folder?(s, id) -> nil
      Map.has_key?(s.shown, id) -> to(s, i + 1)
      true -> toggle(s, id)
    end
  end

  defp act({:key, "left"}, %{cursor: id} = s, _view) do
    cond do
      folder?(s, id) and Map.has_key?(s.shown, id) -> toggle(s, id)
      s.parents[id] != :root -> {s.paths[s.parents[id]], s.open}
      true -> nil
    end
  end

  defp act({:key, key}, %{cursor: id} = s, _view) when key in ["enter", " "],
    do: if(folder?(s, id), do: toggle(s, id))

  defp act({:click, x, y}, %{top: top, ids: ids} = s, view)
       when x < view.cols and y >= 1 and y <= view.rows - 3 and top + y - 1 < length(ids) do
    id = Enum.at(ids, top + y - 1)
    if folder?(s, id), do: toggle(s, id), else: {s.paths[id], s.open}
  end

  defp act(_event, _s, _view), do: nil

  defp to(%{ids: ids, paths: paths, open: open}, j), do: {paths[Enum.at(ids, j)], open}

  # A folder that holds something: one that opens and closes.
  defp folder?(%{tree: tree}, id), do: tree[id].dir and tree[id].kids != []

  # The folder opened, or closed, with the cursor on it. Never more than the
  # options take: the folder opened longest ago goes first.
  defp toggle(%{paths: paths, open: open}, id) do
    path = paths[id]

    open =
      if path in open,
        do: Enum.reject(open, &(&1 == path)),
        else: Enum.take(open, -255) ++ [path]

    {path, open}
  end

  @impl true
  def describe(%{walk: true}), do: nil

  def describe(%{root: root} = options) do
    layout = layout(options)
    %{cursor: at, paths: paths} = still(layout, options)
    root = String.replace(root, ["\n", "\r"], " ")
    name = if root == "", do: "file tree", else: "file tree of " <> Text.slice(root, 0, 200)
    at = if at, do: "; at " <> Text.slice(paths[at], 0, 200), else: ""
    "#{name}: #{count(layout.folders, "folder")}, #{count(layout.files, "file")}" <> at
  end

  defp count(1, noun), do: "1 " <> noun
  defp count(n, noun), do: "#{n} #{noun}s"

  # This port's own: the parts of a frame, read off its lines. The first is
  # the root, the last the count, and those between the listing: the
  # branches before each entry (an arrow at the cursor), its name, and a
  # closed folder's marker.

  @entry ~r/^( *)((?:│   |    )*)([├└]─)(─|>)( )(.*?)( \+)?( *)$/u
  @text ~r/^( *)(.*?)( *)$/u
  @ext ~r/^[a-z0-9_+-]+$/

  @impl true
  def parts(%{lines: lines}, _options) do
    last = length(lines) - 1

    for {line, y} <- Enum.with_index(lines) do
      cond do
        y == 0 -> Parts.captures(line, @text, [nil, "root", nil])
        y == last -> Parts.captures(line, @text, [nil, "summary", nil])
        true -> entry(line)
      end
    end
  end

  defp entry(line) do
    case Regex.run(@entry, line, capture: :all_but_first) do
      [pad, indent, branch, tip, gap, name, marker, trail] ->
        # A marker only ever follows a folder: on a file it is in the name.
        {name, marker} =
          if String.ends_with?(name, "/"), do: {name, marker}, else: {name <> marker, ""}

        at = if tip == ">", do: "cursor", else: "branch"

        Parts.merge([
          {nil, pad},
          {"branch", indent},
          {at, branch <> tip},
          {nil, gap},
          {kind(name), name},
          {"marker", marker},
          {nil, trail}
        ])

      nil ->
        Parts.chars(line, &if(&1 in ["│", "├", "└", "─"], do: "branch"))
    end
  end

  defp kind(name) do
    cond do
      String.ends_with?(name, "/") -> "folder"
      ext = extension(name) -> "file." <> ext
      true -> "file"
    end
  end

  # The extension of a name, in lowercase, if it has one a part's name can
  # hold; not a dotfile's.
  defp extension(name) do
    case name |> String.downcase() |> String.split(".") do
      [_name] -> nil
      ["" | _] -> nil
      parts -> parts |> List.last() |> then(&if(&1 =~ @ext, do: &1))
    end
  end
end
