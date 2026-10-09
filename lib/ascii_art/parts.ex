defmodule AsciiArt.Parts do
  @moduledoc """
  The parts of a piece, coloured one by one: a file tree's folders, files and
  branches, a boot log's `OK` and `WARN`, a chart's bars and axes.

  A piece in one ink that knows its parts lists them in its meta
  (`AsciiArt.Meta`, `parts`) and labels each frame's cells with them (the
  optional `c:AsciiArt.Piece.parts/2`). Give colours for some of them with
  the `:parts` option, and those cells are drawn in them:

      AsciiArt.new("file-tree", parts: %{"folder" => "#58a6ff", "file.md" => "#d29922"})
      AsciiArt.new("boot-log", parts: %{"status.ok" => "#3fb950", "status.warn" => "#d29922"})
      AsciiArt.new("boot-log", parts: true)

  `true` takes the colours the piece suggests for its parts, for a dark
  page, or with `paper: true` for a light one (`suggested/2`). A part it
  suggests none for takes its parent's (a form's `frame.input` the
  `frame`'s), or the ink if it has no parent with one. To change a few of
  them, merge yours over the meta's:

      suggested = AsciiArt.Parts.suggested(AsciiArt.meta!("file-tree"))
      AsciiArt.new("file-tree", parts: Map.merge(suggested, %{"folder" => "#ffffff"}))

  A colour can be a CSS variable, so parts follow a page's theme, light or
  dark: `%{"status.ok" => "var(--color-success, #3fb950)"}` (see
  `AsciiArt.Ink`).

  ## Names

  A part's name is lowercase words joined by dots, the most general first,
  as in tree-sitter's highlight names: `status`, `status.ok`, `file.ts`. A
  colour for a name colours every part under it unless that part has its
  own: `file` colours every file, `file.ts` only TypeScript files. A name
  given `nil` takes the base ink, so `%{"file" => "#c9d1d9", "file.md" => nil}`
  leaves Markdown files out.

  Each piece's docs list its parts. The first word of every name you give
  must be one of them; the rest can be anything (a file's extension, a
  flight's remark), and simply never matches if the piece never uses it.

  ## Over the ink

  Parts are laid over the `:ink`: cells in a part with a colour take it, all
  others the ink (one colour, or a gradient), or the renderer's own ink if
  there is none. In a frame, that last is a `nil` entry in the palette (see
  `AsciiArt.Frame`). The picture itself is never changed: parts are read
  off it after the piece has drawn it.

  ## Labelling a frame

  For a piece of your own, `parts/2` returns each row of the frame as runs
  of `{name, text}`, `name` being `nil` for cells in no part. The runs' text
  must make up the row exactly. The helpers here build runs from a line.
  """

  alias AsciiArt.{Ink, Meta}
  alias AsciiArt.Kit.Palette

  @max_parts 64
  @name ~r/^[a-z0-9_-]+(\.[a-z0-9_+-]+)*$/

  @typedoc "A part's name: lowercase words joined by dots, as `status.ok`."
  @type name :: String.t()

  @typedoc "Some of a row's text, and the part it is in (or `nil`)."
  @type run :: {name() | nil, String.t()}

  @typedoc "A frame's rows, each as runs of text that make up the row."
  @type t :: [[run()]]

  @typedoc "Colours for parts by name, `nil` for the base ink, as `cast/2` makes them."
  @type colors :: %{optional(name()) => String.t() | nil}

  @doc """
  Colours for a piece's parts, from outside: a map or keyword list of names
  (atoms or strings) to colours (`#rrggbb` or a CSS variable, as for `:ink`,
  or `nil`), `true` for the colours the piece suggests (`suggested/2`), or
  `nil` for none. With `paper: true`, the suggestions are those for a light
  page. Never creates an atom.
  """
  @spec cast(parts :: term(), meta :: Meta.t(), opts :: [paper: boolean()]) ::
          {:ok, colors()} | AsciiArt.Options.error()
  def cast(parts, meta, opts \\ [])
  def cast(nil, _meta, _opts), do: {:ok, %{}}
  def cast(false, _meta, _opts), do: {:ok, %{}}
  def cast(true, %Meta{} = meta, opts), do: {:ok, suggested(meta, opts)}

  def cast(parts, %Meta{} = meta, _opts) when is_map(parts) or is_list(parts) do
    known = MapSet.new(meta.parts, fn {name, _} -> first(name) end)

    if Enum.count(parts) > @max_parts,
      do: {:error, {:invalid_option, :parts}},
      else: Enum.reduce_while(parts, {:ok, %{}}, &cast_part(&1, &2, known))
  end

  def cast(_parts, _meta, _opts), do: {:error, {:invalid_option, :parts}}

  # The suggested colours, tuned for a dark page, and theirs for a light
  # one: GitHub's own pairs (Primer's dark and light), so a part keeps its
  # meaning on either.
  @light %{
    "#3fb950" => "#1a7f37",
    "#d29922" => "#9a6700",
    "#f85149" => "#cf222e",
    "#58a6ff" => "#0969da",
    "#39c5cf" => "#1b7c83",
    "#a371f7" => "#8250df",
    "#db61a2" => "#bf3989",
    "#db6d28" => "#bc4c00",
    "#8b949e" => "#6e7781"
  }

  @doc """
  The colours a piece suggests for its parts (its meta's `parts`, those it
  gives one), as `parts: true` takes them: for a dark page, or with
  `paper: true` for a light one. On paper, the shared colours become their
  light-page pairs, and any other is darkened until it reads on white.

      iex> AsciiArt.Parts.suggested(AsciiArt.meta!("boot-log"))["status.ok"]
      "#3fb950"
      iex> AsciiArt.Parts.suggested(AsciiArt.meta!("boot-log"), paper: true)["status.ok"]
      "#1a7f37"
  """
  @spec suggested(meta :: Meta.t(), opts :: [paper: boolean()]) :: colors()
  def suggested(%Meta{parts: parts}, opts \\ []) do
    paper? = Keyword.get(opts, :paper, false) == true
    for {name, color} <- parts, color != nil, into: %{}, do: {name, on_paper(color, paper?)}
  end

  defp on_paper(color, false), do: color
  defp on_paper(color, true), do: Map.get_lazy(@light, color, fn -> darken(color) end)

  # Steps towards black until it stands 4.5 to 1 against white, as WCAG asks
  # of text.
  defp darken(color) do
    {r, g, b} = Palette.rgb255(color)

    if contrast({r, g, b}) >= 4.5,
      do: color,
      else:
        darken(
          "#" <> Base.encode16(<<round(r * 0.9), round(g * 0.9), round(b * 0.9)>>, case: :lower)
        )
  end

  defp contrast(rgb), do: 1.05 / (luminance(rgb) + 0.05)

  defp luminance({r, g, b}) do
    [r, g, b] = for c <- [r, g, b], do: linear(c / 255)
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  defp linear(c) when c <= 0.04045, do: c / 12.92
  defp linear(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

  defp cast_part({key, color}, {:ok, acc}, known) when is_atom(key) or is_binary(key) do
    name = key |> to_string() |> String.downcase()

    with true <- name =~ @name and MapSet.member?(known, first(name)),
         {:ok, color} <- color(color) do
      {:cont, {:ok, Map.put(acc, name, color)}}
    else
      _ -> {:halt, {:error, {:invalid_option, {:parts, key}}}}
    end
  end

  defp cast_part(other, _acc, _known), do: {:halt, {:error, {:invalid_option, {:parts, other}}}}

  defp color(nil), do: {:ok, nil}
  defp color(""), do: {:ok, nil}

  defp color(color) do
    case Ink.color(color) do
      nil -> :error
      color -> {:ok, color}
    end
  end

  defp first(name), do: name |> :binary.split(".") |> hd()

  @doc """
  The name a colour is looked up by next, if `name` has none: the name
  without its last word, or `nil` for a name of one word.

      iex> AsciiArt.Parts.parent("status.ok")
      "status"
      iex> AsciiArt.Parts.parent("status")
      nil
  """
  @spec parent(name :: name()) :: name() | nil
  def parent(name) do
    case :binary.matches(name, ".") do
      [] -> nil
      matches -> binary_part(name, 0, matches |> List.last() |> elem(0))
    end
  end

  @doc """
  The run of a row (as `parts/2` gives it) that holds column `x`, from 0:
  its part and its text. `nil` past the row's end.

      iex> AsciiArt.Parts.run_at([{nil, "  "}, {"status.ok", "[ OK ]"}, {nil, " up"}], 4)
      {"status.ok", "[ OK ]"}
  """
  @spec run_at(runs :: [run()] | nil, x :: non_neg_integer()) :: run() | nil
  def run_at(nil, _x), do: nil
  def run_at([], _x), do: nil

  def run_at([{_name, text} = run | runs], x) do
    n = for <<_::utf8 <- text>>, reduce: 0, do: (n -> n + 1)
    if x < n, do: run, else: run_at(runs, x - n)
  end

  # Helpers for a piece's parts/2.

  @doc "A whole line in one part, or (`nil`) in none."
  @spec line(line :: String.t(), name :: name() | nil) :: [run()]
  def line(line, name), do: [{name, line}]

  @doc """
  A line labelled by a regex that matches all of it: each capture is in the
  part named at its place in `names` (`nil` for none), and text no capture
  holds in no part. Captures that matched nothing are left out. `nil` if the
  regex does not match.

      iex> AsciiArt.Parts.captures("  [ OK ] done", ~r/^ *(\\[ OK \\]) (.*)$/, ["status.ok", "message"])
      [{nil, "  "}, {"status.ok", "[ OK ]"}, {nil, " "}, {"message", "done"}]
  """
  @spec captures(line :: String.t(), regex :: Regex.t(), names :: [name() | nil]) ::
          [run()] | nil
  def captures(line, regex, names) do
    case Regex.run(regex, line, return: :index) do
      nil ->
        nil

      [_whole | groups] ->
        {runs, at} =
          groups
          |> Enum.zip(names)
          |> Enum.reject(fn {{start, len}, _name} -> start < 0 or len == 0 end)
          |> Enum.reduce({[], 0}, fn {{start, len}, name}, {runs, at} ->
            runs =
              if start > at, do: [{nil, binary_part(line, at, start - at)} | runs], else: runs

            {[{name, binary_part(line, start, len)} | runs], start + len}
          end)

        runs =
          if at < byte_size(line),
            do: [{nil, binary_part(line, at, byte_size(line) - at)} | runs],
            else: runs

        runs |> Enum.reverse() |> merge()
    end
  end

  @doc """
  A line labelled by the first of `patterns`, each `{regex, names}` as for
  `captures/3`, that matches all of it; in no part if none does.

      iex> AsciiArt.Parts.first("[WARN] low", [{~r/^(\\[OK\\]) (.*)$/, ["ok", "text"]}, {~r/^(\\[WARN\\]) (.*)$/, ["warn", "text"]}])
      [{"warn", "[WARN]"}, {nil, " "}, {"text", "low"}]
  """
  @spec first(line :: String.t(), patterns :: [{Regex.t(), [name() | nil]}]) :: [run()]
  def first(line, patterns) do
    Enum.find_value(patterns, [{nil, line}], fn {regex, names} ->
      captures(line, regex, names)
    end)
  end

  @doc """
  A line labelled where a regex matches it: each match in the part `name`
  gives (a name, or a function of the matched text returning one), and the
  rest in no part.

      iex> AsciiArt.Parts.matches("a1 b22", ~r/\\d+/, "digit")
      [{nil, "a"}, {"digit", "1"}, {nil, " b"}, {"digit", "22"}]
  """
  @spec matches(
          line :: String.t(),
          regex :: Regex.t(),
          name :: name() | (String.t() -> name() | nil)
        ) :: [run()]
  def matches(line, regex, name) do
    namer = if is_function(name, 1), do: name, else: fn _text -> name end

    {runs, at} =
      regex
      |> Regex.scan(line, return: :index)
      |> Enum.reduce({[], 0}, fn [{start, len} | _], {runs, at} ->
        runs = if start > at, do: [{nil, binary_part(line, at, start - at)} | runs], else: runs
        text = binary_part(line, start, len)
        {[{namer.(text), text} | runs], start + len}
      end)

    runs =
      if at < byte_size(line),
        do: [{nil, binary_part(line, at, byte_size(line) - at)} | runs],
        else: runs

    runs |> Enum.reverse() |> merge()
  end

  @doc """
  A line labelled a character at a time, by a function of each character
  returning its part's name (or `nil`). Neighbours in one part are one run.

      iex> AsciiArt.Parts.chars("██░░", &if(&1 == "█", do: "done", else: "left"))
      [{"done", "██"}, {"left", "░░"}]
  """
  @spec chars(line :: String.t(), fun :: (String.t() -> name() | nil)) :: [run()]
  def chars(line, fun), do: walk(line, fn c, _column -> fun.(<<c::utf8>>) end)

  @doc """
  A line labelled a cell at a time, by a function of each cell's code point
  (an integer, as `?█`) and its column from 0: for pieces whose parts go by
  where a cell is as well as what it holds. Neighbours in one part are one
  run.

      iex> AsciiArt.Parts.cells("▁▁▁▁", fn ?▁, column -> if column < 2, do: "low", else: "high" end)
      [{"low", "▁▁"}, {"high", "▁▁"}]
  """
  @spec cells(line :: String.t(), fun :: (char(), non_neg_integer() -> name() | nil)) :: [run()]
  def cells(line, fun), do: walk(line, fun)

  # One pass over the line's bytes: `start` is the byte the run so far
  # begins at, `at` the next cell's, and each run is cut from the line once
  # its part changes.
  defp walk(line, fun), do: walk(line, fun, line, 0, 0, 0, :start, [])

  defp walk(<<c::utf8, rest::binary>>, fun, line, column, start, at, name, acc) do
    size = utf8_size(c)

    case fun.(c, column) do
      ^name ->
        walk(rest, fun, line, column + 1, start, at + size, name, acc)

      other ->
        walk(rest, fun, line, column + 1, at, at + size, other, run(line, start, at, name, acc))
    end
  end

  defp walk(<<>>, _fun, line, _column, start, at, name, acc),
    do: Enum.reverse(run(line, start, at, name, acc))

  defp run(_line, start, start, _name, acc), do: acc
  defp run(line, start, at, name, acc), do: [{name, binary_part(line, start, at - start)} | acc]

  defp utf8_size(c) when c < 0x80, do: 1
  defp utf8_size(c) when c < 0x800, do: 2
  defp utf8_size(c) when c < 0x10000, do: 3
  defp utf8_size(_c), do: 4

  @doc """
  Runs with neighbours in one part made one, and empty runs dropped. Runs
  can be built a piece at a time, then tidied with this.
  """
  @spec merge(runs :: [run()]) :: [run()]
  def merge(runs) do
    runs
    |> Enum.reject(fn {_name, text} -> text == "" end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{name, _} | _] = chunk -> {name, Enum.map_join(chunk, &elem(&1, 1))} end)
  end

  @doc """
  Runs labelled by `fun` where they are in no part yet, its runs taking
  their place: for labelling in passes, the plain text left by one pass
  given to the next.
  """
  @spec refine(runs :: [run()], fun :: (String.t() -> [run()])) :: [run()]
  def refine(runs, fun) do
    runs
    |> Enum.flat_map(fn
      {nil, text} -> fun.(text)
      run -> [run]
    end)
    |> merge()
  end
end
