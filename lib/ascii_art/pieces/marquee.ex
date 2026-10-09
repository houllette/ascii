defmodule AsciiArt.Pieces.Marquee do
  @moduledoc """
  A scrolling led sign framed by chasing bulbs.

  A theatre sign. Its text scrolls across an LED panel a pixel at a time and
  loops without a seam, while the bulbs round the edge chase. Give it your
  own text: an announcement, a status line, a headline.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): the sign
  starts afresh with them, its text from the start.

    * `text` - what scrolls, in a 5×7 pixel face, upper case: letters,
      digits and common punctuation, any other character drawn as `?`.
      Space at either end is trimmed, and a gap of 12 pixel columns closes
      the loop, so end the text with a separator (` · `) to part one pass
      from the next. Default `"now showing · doors open at 7:30 ·"`.
    * `speed` - pixel columns a second the text moves. Default 12.

  The sign is always 61 by 10.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `AsciiArt.Ink`); part by part with `:parts` (see `AsciiArt.Parts`),
  `parts: true` taking the colours suggested here:

    * `bulb.on`, `bulb.off` - the bulbs round the edge, lit (`o`, yellow)
      and dark (`·`, grey).
    * `frame` - the sign's double-line border, grey.
    * `text` - the lit pixels of the scrolling text.

  ## Keys and clicks

  It takes none: it is a sign, and `AsciiArt.handle_event/2` ignores every
  event. A Phoenix player given `interactive` and `notify` still tells your
  LiveView where it was clicked, and on which part (`AsciiArt.part_at/4`):
  the text, say, or a bulb.

  ## Screen readers

  `AsciiArt.describe/1` reads the text, the `·` that part its messages as
  commas: "marquee: doors at 8, bar open". Without text, it gives the
  piece's name and note.

  ## Example

  ```elixir
  sign = AsciiArt.new!("marquee", options: %{text: "doors at 8 · bar open ·", speed: 20}, ink: "#ffb000")
  {frame, sign} = AsciiArt.frame(sign, 1.0)
  frame.palette
  #=> ["#ffb000"]

  AsciiArt.describe(sign)
  #=> "marquee: doors at 8, bar open"
  ```

  ```heex
  <AsciiArt.Phoenix.live_player id="sign" piece="marquee" options={%{text: @headline <> " ·"}} parts />
  ```

  Ported from `src/pieces/marquee.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{JSMath, Parts}
  alias AsciiArt.Kit.Grid
  import Bitwise, only: [&&&: 2, >>>: 2, <<<: 2, |||: 2]

  @meta %AsciiArt.Meta{
    name: "marquee",
    category: :type,
    note: "a scrolling led sign framed by chasing bulbs",
    cols: 61,
    rows: 10,
    fps: 24,
    options: %{text: "now showing · doors open at 7:30 ·", speed: 12},
    loop: 141,
    parts: [
      {"bulb.on", "#d29922"},
      {"bulb.off", "#8b949e"},
      {"frame", "#8b949e"},
      {"text", nil}
    ]
  }

  # 5x7 glyphs: the character, then one base-32 digit per row (bit 4 is the left pixel).
  @packed "0ehjlphe14c4444e2eh1248v3v2421he426aiv225vgu11he668guhhe7v1248888ehhehhe9ehhf12c" <>
            "AehhvhhhBuhhuhhuCehgggheDuhhhhhuEvgguggvFvggugggGehgnhhfHhhhvhhhIe44444eJ72222ic" <>
            "KhikokihLggggggvMhrllhhhNhhpljhhOehhhhhePuhhugggQehhhlidRuhhukihSfgge11uTv444444" <>
            "UhhhhhheVhhhhha4WhhhlllaXhha4ahhYhha4444Zv1248gv.0000004,0000048:0040040!4444404" <>
            "?eh12404-000e000'4400000\"aa00000/11248gg&cik8lid+044v440·0004000*04lel40#aavavaa" <>
            "(2488842)8422248@ehnlngf%op248j3=00v0v00_000000v 0000000"
  @font @packed
        |> String.codepoints()
        |> Enum.chunk_every(8)
        |> Map.new(fn [ch | digits] -> {ch, Enum.map(digits, &String.to_integer(&1, 32))} end)

  # The panel, inside the frame, and the first of the four rows the letters light.
  @left 4
  @width @meta.cols - 8
  @band 3

  @impl true
  def meta, do: @meta

  # The text as a strip of pixel columns, each a 7-bit mask with bit 0 at the top.
  defp strip(text) do
    text
    |> String.upcase()
    |> String.codepoints()
    |> Enum.flat_map(fn ch ->
      g = Map.get(@font, ch, @font["?"])

      cs =
        if ch == " " do
          [0, 0, 0]
        else
          a = for x <- 0..4, do: column(g, x)

          # Blank columns stay only between inked ones.
          for {m, x} <- Enum.with_index(a),
              m != 0 or
                (Enum.any?(Enum.take(a, x), &(&1 != 0)) and Enum.any?(Enum.drop(a, x), &(&1 != 0))),
              do: m
        end

      cs ++ [0]
    end)
  end

  defp column(g, x) do
    g
    |> Enum.with_index()
    |> Enum.reduce(0, fn {b, y}, m -> m ||| if((b &&& 16 >>> x) != 0, do: 1 <<< y, else: 0) end)
  end

  @impl true
  def init(%{text: text, speed: speed}) do
    %{cols: cols, rows: rows} = @meta
    # Pad the loop with a gap, then repeat it until it is wider than the panel.
    unit = strip(js_trim(text)) ++ List.duplicate(0, 12)
    loop = grow(unit, unit)

    # Bulbs every other cell along the top and bottom, every row down the sides,
    # numbered clockwise so a chase can run round them.
    bulbs =
      Enum.map(0..(cols - 1)//2, &{0, &1}) ++
        Enum.map(1..(rows - 2), &{&1, cols - 1}) ++
        Enum.map((cols - 1)..0//-2, &{rows - 1, &1}) ++
        Enum.map((rows - 2)..1//-1, &{&1, 0})

    # The sign's frame, inset from the bulbs.
    base =
      Grid.new(cols, rows)
      |> Grid.put(2, 1, "╔")
      |> Grid.put(cols - 3, 1, "╗")
      |> Grid.put(2, rows - 2, "╚")
      |> Grid.put(cols - 3, rows - 2, "╝")

    base =
      Enum.reduce(3..(cols - 4), base, fn c, g ->
        g |> Grid.put(c, 1, "═") |> Grid.put(c, rows - 2, "═")
      end)

    base =
      Enum.reduce(2..(rows - 3), base, fn r, g ->
        g |> Grid.put(2, r, "║") |> Grid.put(cols - 3, r, "║")
      end)

    %{loop: List.to_tuple(loop), speed: speed, bulbs: Enum.with_index(bulbs), base: base}
  end

  # JS's String.prototype.trim, which takes off WhiteSpace and LineTerminator.
  defp js_trim(s) do
    String.replace(
      s,
      ~r/\A[\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]+|[\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]+\z/u,
      ""
    )
  end

  defp grow(loop, unit) when length(loop) < @width + 1, do: grow(loop ++ unit, unit)
  defp grow(loop, _unit), do: loop

  @impl true
  def frame(%{loop: loop, bulbs: bulbs} = state, t, _env) do
    l = tuple_size(loop)
    off = rem(JSMath.floor(t * state.speed), l)

    grid =
      for j <- 0..(@width - 1), i <- 0..3, reduce: state.base do
        g ->
          # Past the start of the loop, a negative offset reads undefined: no pixels.
          k = rem(off + j, l)
          m = if k < 0, do: 0, else: elem(loop, k)
          # Each cell holds two pixel rows; the letters sit one pixel down.
          top = if i == 0, do: 0, else: m >>> (2 * i - 1) &&& 1
          bot = m >>> (2 * i) &&& 1
          Grid.put(g, @left + j, @band + i, cell(top, bot))
      end

    # Two of every three bulbs lit, the dark one walking clockwise.
    step = JSMath.floor(t * 7)

    grid =
      Enum.reduce(bulbs, grid, fn {{r, c}, i}, g ->
        Grid.put(g, c, r, if(Integer.mod(i - step, 3) == 0, do: "·", else: "o"))
      end)

    {Grid.to_iodata(grid), nil, state}
  end

  defp cell(1, 1), do: "█"
  defp cell(1, 0), do: "▀"
  defp cell(0, 1), do: "▄"
  defp cell(0, 0), do: " "

  # This port's own: the parts of a frame, by glyph. Each kind of thing on
  # the sign is drawn in glyphs of its own: bulbs as `o` and `·`, the frame
  # in double lines, the panel's pixels in blocks.

  @frame ["╔", "╗", "╚", "╝", "═", "║"]
  @pixels ["█", "▀", "▄"]

  @impl true
  def parts(%{lines: lines}, _options),
    do: Enum.map(lines, &Parts.chars(&1, fn ch -> part(ch) end))

  defp part("o"), do: "bulb.on"
  defp part("·"), do: "bulb.off"
  defp part(ch) when ch in @frame, do: "frame"
  defp part(ch) when ch in @pixels, do: "text"
  defp part(_blank), do: nil

  # This port's own: the sign's text, for a screen reader, the dots that
  # part its messages read as commas.
  @impl true
  def describe(%{text: text}) do
    said =
      text
      |> String.split()
      |> Enum.reduce([], fn
        "·", [] -> []
        "·", [last | said] -> [String.trim_trailing(last, ",") <> "," | said]
        word, said -> [word | said]
      end)
      |> Enum.reverse()
      |> Enum.join(" ")
      |> String.trim_trailing(",")

    if said != "", do: "marquee: " <> said
  end
end
