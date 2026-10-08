defmodule AsciiArt.Pieces.Marquee do
  @moduledoc """
  A scrolling led sign framed by chasing bulbs.

  A theatre sign. Its text scrolls across an LED panel a pixel at a time and
  loops without a seam, while the bulbs round the edge chase.

  Ported from `src/pieces/marquee.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
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
    loop: 141
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
end
