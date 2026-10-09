defmodule AsciiArt.Pieces.NotFound do
  @moduledoc """
  A block-letter 404 with a small ghost drifting beneath it.

  A 404 page. The code in heavy block digits with a double-line shadow, a
  small ghost drifting to and fro beneath it, and a line of copy: your
  error page's, in your words, for any code.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): the page
  is drawn anew from them, the ghost drifting on.

    * `code` - the digits set big: the first three digits in it, as
      `"500"`; with none, `404`. Default `"404"`.
    * `title` - the first line of copy, centred under the ghost. Default
      `"page not found"`.
    * `message` - the line under it. Default `"the page you asked for has
      moved or never existed"`.

  Lines of copy longer than the frame's 60 columns are cut. The frame is
  60 by 21, and the ghost's drift comes round every 9 seconds.

  ## Colours

  It has no parts to colour one by one: in one ink, or a gradient, with
  `:ink` and `:gradient` (see `AsciiArt.Ink`). A vertical gradient sets
  the digits, the ghost and the copy in colours of their own.

  ## Keys and clicks

  It takes none: it is a page to read, and `AsciiArt.handle_event/2`
  ignores every event. A Phoenix player given `interactive` and `notify`
  still tells your LiveView where it was clicked.

  ## Screen readers

  `AsciiArt.describe/1` reads the code and the copy, as "404: page not
  found; the page you asked for has moved or never existed".

  ## Example

  ```elixir
  options = %{code: "500", title: "server error", message: "we are on it"}
  page = AsciiArt.new!("not-found", options: options, ink: "#f85149")
  AsciiArt.describe(page)
  #=> "500: server error; we are on it"
  ```

  ```heex
  <AsciiArt.Phoenix.Components.ascii piece="not-found" options={%{code: "503", title: "back soon"}} />
  ```

  Ported from `src/pieces/not-found.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Text
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "not found",
    category: :ui,
    note: "a block-letter 404 with a small ghost drifting beneath it",
    cols: 60,
    rows: 21,
    fps: 15,
    options: %{
      code: "404",
      title: "page not found",
      message: "the page you asked for has moved or never existed"
    },
    loop: 9
  }

  # A 3x5 font, each font column drawn 4 cells wide and the rows 2,1,2,1,2
  # cells tall, so a digit is 12x8 and strokes are as thick across as down.
  @font %{
    "0" => "###,#.#,#.#,#.#,###",
    "1" => "##.,.#.,.#.,.#.,###",
    "2" => "###,..#,###,#..,###",
    "3" => "###,..#,###,..#,###",
    "4" => "#.#,#.#,###,..#,..#",
    "5" => "###,#..,###,..#,###",
    "6" => "###,#..,###,#.#,###",
    "7" => "###,..#,..#,..#,..#",
    "8" => "###,#.#,###,#.#,###",
    "9" => "###,#.#,###,..#,###"
  }
  @rh [2, 1, 2, 1, 2]
  @dw 12
  @dh 8
  @gap 4
  # First row of the digits.
  @top 1

  # The ghost in square pixels, two to a cell, top half and bottom half.
  @body [
    "..####..",
    ".######.",
    "########",
    "########",
    "########",
    "########",
    "########",
    "########",
    "########"
  ]
  @hems {".##..##.", "#..##..#"}
  @gw 8
  # Left column of each eye hole, two wide and four tall.
  @eyes [1, 5]
  # Seconds for one trip there and back.
  @period 9
  # The ghost's resting top in half rows. It bobs a half row either way and
  # always leaves a clear row under the digits' shadow.
  @band (@top + @dh + 2) * 2 + 1

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{code: code, title: title, message: message}) do
    %{cols: cols, rows: rows} = @meta

    digits =
      code
      |> String.replace(~r/[^0-9]/u, "")
      |> String.slice(0, 3)
      |> String.graphemes()

    digits = if digits == [], do: ["4", "0", "4"], else: digits
    n = length(digits)
    width = n * @dw + (n - 1) * @gap + 1
    x0 = floor((cols - width) / 2)

    face =
      for {d, i} <- Enum.with_index(digits),
          {bits, r} <- font_rows(d),
          {"#", fc} <- bits |> String.graphemes() |> Enum.with_index(),
          c <- 0..3,
          into: MapSet.new(),
          do: linear(r * cols + x0 + i * (@dw + @gap) + fc * 4 + c)

    # The shadow is the face moved one cell down and right, traced in double lines.
    at = fn r, c -> r >= 0 and c >= 0 and r < rows and c < cols and {r, c} in face end

    base =
      for r <- 0..(rows - 1), c <- 0..(cols - 1), into: %{} do
        {{r, c},
         if(at.(r, c), do: "█", else: shadow(at.(r, c - 1), at.(r - 1, c), at.(r - 1, c - 1)))}
      end

    base =
      base
      |> put(@top + @dh + 9, title)
      |> put(@top + @dh + 10, message)

    cells =
      for r <- 0..(rows - 1) do
        List.to_tuple(for c <- 0..(cols - 1), do: base[{r, c}])
      end

    %{
      cells: List.to_tuple(cells),
      lines:
        cells |> Enum.map(&(&1 |> Tuple.to_list() |> IO.iodata_to_binary())) |> List.to_tuple()
    }
  end

  # Writes into the flat buffer upstream keeps: an index past a row's end
  # runs on into the next row.
  defp linear(k), do: {div(k, @meta.cols), rem(k, @meta.cols)}

  defp font_rows(d) do
    {rows, _} =
      @font[d]
      |> String.split(",")
      |> Enum.zip(@rh)
      |> Enum.flat_map_reduce(@top, fn {bits, h}, r ->
        {for(k <- 0..(h - 1), do: {bits, r + k}), r + h}
      end)

    rows
  end

  defp shadow(true, true, _ul), do: "╔"
  defp shadow(true, false, true), do: "║"
  defp shadow(true, false, false), do: "╗"
  defp shadow(false, true, true), do: "═"
  defp shadow(false, true, false), do: "╚"
  defp shadow(false, false, true), do: "╝"
  defp shadow(false, false, false), do: " "

  defp put(base, r, s) do
    s = Text.slice(s, 0, @meta.cols)
    c0 = floor((@meta.cols - Text.length(s)) / 2)

    s
    |> String.codepoints()
    |> Enum.with_index()
    |> Enum.reduce(base, fn {ch, i}, base ->
      Map.put(base, linear(r * @meta.cols + c0 + i), ch)
    end)
  end

  @impl true
  def frame(%{cells: cells, lines: lines} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    ph = t / @period * :math.pi() * 2
    gx = JSMath.round(cols / 2 - @gw / 2 + 18 * :math.sin(ph))
    gy = @band + JSMath.round(:math.sin(t / 1.5 * :math.pi() * 2))
    # 1 heading right.
    look = if :math.cos(ph) >= 0, do: 1, else: 0

    shape = @body ++ [elem(@hems, rem(floor(t * 4), 2))]

    px =
      for {line, y} <- Enum.with_index(shape),
          {"#", x} <- line |> String.graphemes() |> Enum.with_index(),
          into: MapSet.new(),
          do: {gy + y, gx + x}

    # Eye holes sit on whole cells, so each shows a clear white cell above a
    # pupil: one half block in the bottom corner it is heading toward.
    ey = (gy + 3) |> bsr(1) |> bsl(1)

    px =
      Enum.reduce(@eyes, px, fn ex, px ->
        e = gx + ex
        holes = for y <- 0..3, x <- [e, e + 1], do: {ey + y, x}
        px |> MapSet.difference(MapSet.new(holes)) |> MapSet.put({ey + 3, e + look})
      end)

    out =
      for r <- 0..(rows - 1) do
        if 2 * r + 1 < gy or 2 * r > gy + 9 do
          elem(lines, r)
        else
          row = elem(cells, r)

          for c <- 0..(cols - 1) do
            case {{2 * r, c} in px, {2 * r + 1, c} in px} do
              {true, true} -> "█"
              {true, false} -> "▀"
              {false, true} -> "▄"
              {false, false} -> elem(row, c)
            end
          end
        end
      end

    {Enum.intersperse(out, ?\n), nil, state}
  end

  # This port's own: the page's words, for a screen reader.
  @impl true
  def describe(%{code: code, title: title, message: message}) do
    case {words(code), for(s <- [title, message], said = words(s), said != "", do: said)} do
      {"", []} -> nil
      {code, []} -> code
      {"", said} -> "not found: " <> Enum.join(said, "; ")
      {code, said} -> code <> ": " <> Enum.join(said, "; ")
    end
  end

  defp words(s), do: s |> String.split() |> Enum.join(" ")
end
