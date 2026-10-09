defmodule Ascii.Render.SVG do
  @moduledoc """
  A frame as an SVG picture: for an email, a README, a social preview, or
  anywhere an image goes and a `<pre>` cannot.

      {:ok, frame} = Ascii.still("night-coast")
      File.write!("night-coast.svg", Ascii.Render.SVG.render(frame, title: "a lighthouse"))

  Each row is text, in runs of one colour, each run placed at its column
  and held to its width, so the columns line up in whatever monospace font
  the reader has. A coloured piece is drawn over its `ground`; a frame
  without colours, and cells in no coloured part, take `:foreground`. A CSS
  variable in the palette (see `Ascii.Ink`) stays one, so an SVG inlined
  in a page takes the page's colours; on its own, it shows the fallback.
  Spaces are left out: an SVG is about the size of the frame's text.

  ## Options

    * `:font_size` - in pixels (default 14). A cell is 0.6 of it wide, the
      shape of most monospace fonts, and as tall as the piece's `cell` says
      (1.2 of it for a character's shape), as the browser's canvas draws.
    * `:font_family` - the font (default a stack of system monospace fonts).
    * `:foreground` - the colour of uncoloured text (default
      `"currentColor"`, the colour of the text around an inline SVG; black
      in a file of its own).
    * `:background` - a colour behind the picture. Defaults to the piece's
      ground, if it is drawn in colour over one; else none.
    * `:title` - what the picture shows, for screen readers and as its
      tooltip: see `Ascii.describe/1`.
  """

  alias Ascii.{Frame, Ink}

  @font "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"

  @type option ::
          {:font_size, number()}
          | {:font_family, String.t()}
          | {:foreground, String.t()}
          | {:background, String.t() | nil}
          | {:title, String.t()}

  @doc "The frame as an SVG document, as iodata."
  @spec render(frame :: Frame.t(), opts :: [option()]) :: iodata()
  def render(%Frame{} = frame, opts \\ []) do
    size = Keyword.get(opts, :font_size, 14)
    cw = size * 0.6
    lh = cw * frame.cell
    width = frame.cols * cw
    height = frame.rows * lh
    fg = Keyword.get(opts, :foreground, "currentColor")
    title = Keyword.get(opts, :title)

    [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="),
      num(width),
      ~s(" height="),
      num(height),
      ~s(" viewBox="0 0 ),
      num(width),
      " ",
      num(height),
      ~s(" role="img"),
      if(title, do: [~s( aria-label="), escape(title), ?"], else: []),
      ">",
      if(title, do: ["<title>", escape(title), "</title>"], else: []),
      background(Keyword.get(opts, :background, ground(frame))),
      ~s(<g font-family="),
      escape(Keyword.get(opts, :font_family, @font)),
      ~s(" font-size="),
      num(size),
      ~s(" xml:space="preserve" style="white-space:pre"),
      fill(fg, fg),
      ">",
      rows(frame, cw, lh, fg),
      "</g></svg>"
    ]
  end

  defp ground(%Frame{colors: colors, ground: ground}) when colors != nil, do: ground
  defp ground(_frame), do: nil

  defp background(nil), do: []

  defp background(color),
    do: [~s(<rect width="100%" height="100%"), fill(color, "none"), "/>"]

  # Each row as a <text>, a <tspan> a run of one ink, spaces trimmed off it.
  defp rows(%Frame{lines: lines} = frame, cw, lh, fg) do
    palette = frame.palette && List.to_tuple(frame.palette)

    for {line, y} <- Enum.with_index(lines),
        runs = runs(line, row_colors(frame, y)),
        runs != [] do
      [
        ~s(<text y="),
        num((y + 0.5) * lh),
        ~s(" dominant-baseline="central" xml:space="preserve">),
        for {i, x, text} <- runs do
          [
            ~s(<tspan x="),
            num(x * cw),
            ~s(" textLength="),
            num(cells(text) * cw),
            ~s(" lengthAdjust="spacingAndGlyphs"),
            ink(palette, i, fg),
            ">",
            escape(text),
            "</tspan>"
          ]
        end,
        "</text>"
      ]
    end
  end

  defp row_colors(%Frame{colors: nil, cols: cols}, _y), do: :binary.copy(<<0>>, cols)

  defp row_colors(%Frame{colors: colors, cols: cols}, y),
    do: binary_part(colors, y * cols, cols)

  # Runs of one palette index, as {index, column, text}: words in one ink,
  # with single spaces between them, each run placed at its own column. Two
  # spaces or more part runs, so no reader that closes up spaces (as some
  # do, xml:space or not) can shift a column.
  defp runs(line, colors) do
    line
    |> String.codepoints()
    |> Enum.zip(:binary.bin_to_list(colors))
    |> Enum.with_index()
    |> Enum.chunk_while([], &gather/2, &finish/1)
    |> Enum.flat_map(&trimmed/1)
  end

  # Cells gathered into a run until the ink changes or a second space comes.
  defp gather({{ch, i}, _x} = cell, [{{last, j}, _} | _] = run) do
    cond do
      ch == " " and last == " " -> {:cont, run, []}
      ch != " " and last != " " and i != j -> {:cont, run, [cell]}
      ch != " " and last == " " and i != run_ink(run) -> {:cont, run, [cell]}
      true -> {:cont, [cell | run]}
    end
  end

  defp gather({{" ", _i}, _x}, []), do: {:cont, []}
  defp gather(cell, []), do: {:cont, [cell]}

  defp finish(run), do: {:cont, run, []}

  # A run's ink: its first cell's.
  defp run_ink(run), do: run |> List.last() |> elem(0) |> elem(1)

  defp trimmed([]), do: []

  defp trimmed(run) do
    case run |> Enum.drop_while(fn {{ch, _i}, _x} -> ch == " " end) |> Enum.reverse() do
      [] -> []
      [{{_ch, i}, x} | _] = kept -> [{i, x, Enum.map_join(kept, fn {{ch, _i}, _x} -> ch end)}]
    end
  end

  defp cells(text), do: for(<<_::utf8 <- text>>, reduce: 0, do: (n -> n + 1))

  # A run's colour: its palette entry's, or (nil, or no palette) the text's.
  defp ink(nil, _i, _fg), do: []

  defp ink(palette, i, fg) do
    case elem(palette, i) do
      nil -> []
      ^fg -> []
      color -> fill(color, fg)
    end
  end

  # A CSS variable goes in a style, where every browser reads one; on its
  # own, a variable without a fallback falls back to the `fallback`.
  defp fill("var(" <> _ = var, fallback) do
    color =
      case Ink.resolve(var) do
        nil -> String.replace_suffix(var, ")", ", " <> fallback <> ")")
        _hex -> var
      end

    [~s( style="fill:), escape(color), ?"]
  end

  defp fill(color, _fallback), do: [~s( fill="), escape(color), ?"]

  defp num(x) when is_integer(x), do: Integer.to_string(x)

  defp num(x) do
    x
    |> :erlang.float_to_binary(decimals: 2)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp escape(text) do
    for <<c <- IO.iodata_to_binary(text)>>, into: "" do
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
