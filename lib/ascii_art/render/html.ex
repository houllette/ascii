defmodule AsciiArt.Render.HTML do
  @moduledoc """
  A frame as the inside of a `<pre>`: escaped text, and for a coloured frame
  a `<span style="color:...">` a run of one colour.

  Spaces join whatever run they fall in, so a logo is a few dozen spans and
  a full scene a few thousand. That is fine for a still or a logo; to play a
  piece live, `AsciiArt.Phoenix.PlayerLive` sends only what changes.

  Phoenix is not needed: the result is plain iodata, already escaped. Put it
  in a `<pre>` whose style is `style/1`.
  """

  alias AsciiArt.Frame

  @doc "The `<pre>`'s contents, escaped: `rows/1` joined by newlines."
  @spec render(frame :: Frame.t()) :: iodata()
  def render(%Frame{} = frame), do: frame |> rows() |> Enum.intersperse(?\n)

  @doc "Each row's HTML, escaped, without newlines."
  @spec rows(frame :: Frame.t()) :: [iodata()]
  def rows(%Frame{colors: nil, lines: lines}), do: Enum.map(lines, &escape/1)

  def rows(%Frame{palette: palette} = frame) do
    palette = List.to_tuple(palette)

    frame.lines
    |> Enum.with_index()
    |> Enum.map(fn {line, y} -> line_spans(frame, palette, line, y) end)
  end

  @doc "Row `y`'s HTML, as in `rows/1`."
  @spec row(frame :: Frame.t(), y :: non_neg_integer()) :: iodata()
  def row(%Frame{colors: nil, lines: lines}, y), do: lines |> Enum.at(y) |> escape()

  def row(%Frame{palette: palette, lines: lines} = frame, y),
    do: line_spans(frame, List.to_tuple(palette), Enum.at(lines, y), y)

  defp line_spans(%Frame{colors: colors, cols: cols}, palette, line, y) do
    line
    |> String.codepoints()
    |> runs(:binary.bin_to_list(colors, y * cols, cols), nil, [])
    |> spans(palette)
  end

  # Consecutive cells of one colour, spaces in the current one: [{index, chars}].
  defp runs([], [], _current, acc), do: Enum.reverse(acc)

  defp runs([" " | chars], [_ | idx], current, [{c, run} | acc]),
    do: runs(chars, idx, current, [{c, [run, " "]} | acc])

  defp runs([" " | chars], [i | idx], _current, []), do: runs(chars, idx, i, [{i, " "}])

  defp runs([ch | chars], [i | idx], i, [{i, run} | acc]),
    do: runs(chars, idx, i, [{i, [run, ch]} | acc])

  defp runs([ch | chars], [i | idx], _current, acc), do: runs(chars, idx, i, [{i, ch} | acc])

  defp spans(runs, palette) do
    for {i, run} <- runs,
        do: [~s(<span style="color:), elem(palette, i), ~s(">), escape(run), "</span>"]
  end

  @doc "The `<pre>`'s style: the piece's ground behind a coloured frame, else `nil`."
  @spec style(frame :: Frame.t()) :: String.t() | nil
  def style(%Frame{colors: colors, ground: ground}) when colors != nil and ground != nil,
    do: "background:" <> ground

  def style(_frame), do: nil

  @doc "HTML-escapes text (as iodata)."
  @spec escape(text :: iodata()) :: iodata()
  def escape(text), do: text |> IO.iodata_to_binary() |> escape_binary()

  defp escape_binary(s) do
    for <<c <- s>>, into: "" do
      case c do
        ?< -> "&lt;"
        ?> -> "&gt;"
        ?& -> "&amp;"
        ?" -> "&quot;"
        ?' -> "&#39;"
        c -> <<c>>
      end
    end
  end
end
