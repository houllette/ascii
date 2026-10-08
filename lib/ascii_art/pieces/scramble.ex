defmodule AsciiArt.Pieces.Scramble do
  @moduledoc """
  Phrases decoding left to right out of flickering glyphs.

  A decode effect. Each phrase breaks into flickering glyphs from the left,
  and the next one settles out of them a letter at a time.

  Ported from `src/pieces/scramble.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Text
  import Bitwise, only: [bxor: 2, >>>: 2]

  @meta %AsciiArt.Meta{
    name: "scramble",
    category: :type,
    note: "phrases decoding left to right out of flickering glyphs",
    cols: 44,
    rows: 3,
    fps: 20,
    options: %{
      phrases: [
        "hello, world",
        "decoding the signal",
        "nothing is lost",
        "see you on the other side"
      ]
    }
  }

  @glyphs "!<>-_\\/[]{}=+*^?#%&$@0123456789abcdefxyz" |> String.codepoints() |> List.to_tuple()
  # Seconds between columns breaking up; between columns settling; of pure
  # noise before the first column settles; a settled phrase stays.
  @out_gap 0.022
  @in_gap 0.05
  @lead 0.32
  @hold 1.9

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{phrases: phrases}) do
    cols = @meta.cols

    placed =
      for p <- if(phrases == [], do: [""], else: phrases) do
        text = Text.slice(p, 0, cols - 4)
        n = Text.length(text)
        %{text: text |> Text.chars() |> List.to_tuple(), x: JSMath.floor((cols - n) / 2), n: n}
      end

    # One transition per phrase, into it from the one before: when each column
    # breaks up and when it settles, with a little jitter so the front is ragged.
    froms = [List.last(placed) | Enum.drop(placed, -1)]

    {steps, {period, _rand}} =
      Enum.map_reduce(Enum.zip(froms, placed), {0, 77}, fn {from, to}, {at, rand} ->
        lo = min(from.x, to.x)
        hi = max(from.x + from.n, to.x + to.n)

        {times, rand} =
          Enum.map_reduce(lo..(hi - 1)//1, rand, fn c, rand ->
            {a, rand} = Int32.mulberry32(rand)
            {b, rand} = Int32.mulberry32(rand)

            {{at + (c - lo) * @out_gap + a * 0.06, at + @lead + (c - lo) * @in_gap + b * 0.14},
             rand}
          end)

        stop = Enum.reduce(times, at + @lead, fn {_, settle}, m -> max(m, settle) end) + @hold
        step = %{from: from, to: to, lo: lo, hi: hi, times: List.to_tuple(times), end: stop}
        {step, {stop, rand}}
      end)

    # Frame 0 holds the first phrase, settled, just before it breaks up.
    %{steps: steps, period: period, offset: hd(steps).end - 0.7}
  end

  defp char_at(%{x: x, n: n, text: text}, c) when c >= x and c < x + n, do: elem(text, c - x)
  defp char_at(_p, _c), do: " "

  @impl true
  def frame(%{steps: steps, period: period} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    now = JSMath.mod(JSMath.mod(t + state.offset, period) + period, period)
    s = Enum.find(steps, hd(steps), &(now < &1.end))
    tick = JSMath.floor(now * 20)

    line =
      for c <- 0..(cols - 1) do
        if c < s.lo or c >= s.hi, do: " ", else: column(s, c, now, tick)
      end

    blank = String.duplicate(" ", cols)
    lines = for r <- 0..(rows - 1), do: if(r == Int32.sar(rows, 1), do: line, else: blank)
    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp column(s, c, now, tick) do
    {out, settle} = elem(s.times, c - s.lo)
    a = char_at(s.from, c)
    b = char_at(s.to, c)

    cond do
      now < out -> a
      now >= settle -> b
      a == " " and b == " " and now < out + 0.12 -> " "
      true -> glyph(c, tick)
    end
  end

  # A new glyph for this column on every tick, the same in every instance.
  defp glyph(c, tick) do
    h = Int32.umul(Int32.u32(bxor(c, Int32.imul(tick, 0x27D4EB2D))), 0x9E3779B1)
    h = Int32.umul(bxor(h, h >>> 15), 0x85EBCA77)
    elem(@glyphs, rem(bxor(h, h >>> 13), tuple_size(@glyphs)))
  end
end
