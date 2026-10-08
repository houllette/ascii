defmodule AsciiArt.Pieces.FileTree do
  @moduledoc """
  A tree listing opened folder by folder, then closed again.

  A project listed the way `tree -F` prints it, opened one folder at a time
  by a cursor walking down the list, then closed from the bottom up.

  Options: `root`, the first line, above the listing; `entries`, one entry
  per line, two spaces of indent per level, folders end in "/".

  Ported from `src/pieces/file-tree.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Text

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

  @meta %AsciiArt.Meta{
    name: "file tree",
    category: :ui,
    note: "a tree listing opened folder by folder, then closed again",
    cols: 36,
    rows: 23,
    fps: 15,
    options: %{root: ".", entries: @entries}
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
  def init(%{root: label, entries: entries}) do
    %{cols: cols} = @meta
    tree = parse(entries)
    {dirs, nd, nf} = collect(tree, :root, {[], 0, 0})
    dirs = Enum.reverse(dirs)

    # Counted over the whole tree, as tree itself does, not just what is open.
    summary =
      "#{nd} director#{if nd == 1, do: "y", else: "ies"}, #{nf} file#{if nf == 1, do: "", else: "s"}"

    cursor =
      case {dirs, tree[:root].kids} do
        {[first | _], _} -> first
        {[], [first | _]} -> first
        {[], []} -> nil
      end

    # Centre the listing as it stands fully open, with room for the marker.
    open = Map.new(dirs, &{&1, length(tree[&1].kids)})
    shown = Map.put(open, :root, length(tree[:root].kids))
    lengths = for {_, text} <- listing(tree, shown, cursor), do: Text.length(text) + 2
    width = Enum.max([Text.length(label), Text.length(summary) | lengths])
    pad = String.duplicate(" ", max(0, floor((cols - width) / 2)))

    view = %{tree: tree, label: label, summary: summary, pad: pad}

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
    %{cols: cols, rows: rows} = @meta
    %{tree: tree, label: label, summary: summary, pad: pad} = view

    lines =
      Enum.take([label | for({_, text} <- listing(tree, shown, cursor), do: text)], rows - 2)

    lines = lines ++ List.duplicate("", rows - 1 - length(lines)) ++ [summary]

    lines
    |> Enum.map(&((pad <> &1) |> Text.pad_end(cols) |> Text.slice(0, cols)))
    |> Enum.intersperse(?\n)
    |> IO.iodata_to_binary()
  end

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
  def frame(%{snaps: snaps, total: total, start: start} = state, t, _env) do
    p = JSMath.mod(t + start, total)
    {state_text(snaps, p, 0), nil, state}
  end

  defp state_text(snaps, p, i) do
    if i + 1 < tuple_size(snaps) and elem(elem(snaps, i + 1), 0) <= p,
      do: state_text(snaps, p, i + 1),
      else: elem(elem(snaps, i), 1)
  end
end
