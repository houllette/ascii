defmodule AsciiArt.Pieces.MatrixRain do
  @moduledoc """
  Streams of glyphs falling, heavy at the head, thin behind.

  Streams of code falling down a screen, each column at its own pace. The head
  of a stream is the heaviest glyph and the tail thins behind.

  Ported from `src/pieces/matrix-rain.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}

  @meta %AsciiArt.Meta{
    name: "matrix rain",
    category: :effects,
    note: "streams of glyphs falling, heavy at the head, thin behind",
    cols: 63,
    rows: 24,
    fps: 20
  }

  # Glyph sets from heaviest to lightest. A near stream runs head, a lighter
  # collar, a solid body, then thins through the rest; a far one is light all
  # the way down, so the rain has some depth.
  @head "@#%&$"
  @collar "acdeghkmnorsuvxz"
  @body "0123456789ABCDEFHKMNPRSTXZ"
  @thin {"acdeghkmnorsuvxz=+*<>", ":;!|il^~", ".,'`"}
  @far_sets {"=+*<>|", ":;!|il", ":;!|il^~", ".,'`"}
  # Speeds in rows a second, lengths in rows, and the gap after each pass as a
  # share of the screen height: {least, spread}.
  @near %{near?: true, speed: {9, 9}, len: {12, 10}, gap: {0.15, 0.45}}
  @far %{near?: false, speed: {4, 2.5}, len: {10, 6}, gap: {1.1, 1.4}}

  @impl true
  def meta, do: @meta

  # A small integer hash, so a glyph is a function of where and when it is.
  defp hash(a, b, c) do
    h = Int32.imul(a, 374_761_393) + Int32.imul(b, 668_265_263) + Int32.imul(c, 2_246_822_519)
    h = Int32.imul(Int32.bxor(h, Int32.ushr(h, 13)), 1_274_126_177)
    Int32.to_uint32(Int32.bxor(h, Int32.ushr(h, 16))) / 4_294_967_296
  end

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta

    # Near streams run in the even columns and far ones in the odd. Each pass
    # down a column draws its own length and gap, and the columns start spread
    # evenly through their cycles so no stretch of the screen sits dark.
    lanes =
      for c <- 0..(cols - 1) do
        kind = if rem(c, 2) == 1, do: @far, else: @near
        speed = elem(kind.speed, 0) + hash(c, 1, 0) * elem(kind.speed, 1)
        {g0, g1} = kind.gap
        {l0, l1} = kind.len
        cycle = rows * (1 + g0 + g1 / 2) + l0 + l1 / 2
        phase = JSMath.mod(c * 0.618034 + hash(c, 3, 0) * 0.2, 1) * cycle
        %{kind: kind, speed: speed, phase: phase}
      end

    # Each column's pass so far, {k, from}: a cache that only moves forward.
    %{lanes: List.to_tuple(lanes), passes: List.to_tuple(List.duplicate({0, 0}, cols))}
  end

  defp len(c, k, kind), do: elem(kind.len, 0) + JSMath.floor(hash(c, k, 4) * elem(kind.len, 1))

  defp span(c, k, kind) do
    rows = @meta.rows
    rows + len(c, k, kind) + rows * (elem(kind.gap, 0) + hash(c, k, 2) * elem(kind.gap, 1))
  end

  # Steps a column on to the pass its head is in now.
  defp advance(c, kind, u, {k, from}) do
    {k, from} = if u < from, do: {0, 0}, else: {k, from}
    s = span(c, k, kind)
    if u - from >= s, do: advance(c, kind, u, {k + 1, from + s}), else: {k, from}
  end

  @impl true
  def frame(state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    tick = JSMath.floor(t * 20)

    {cells, passes} =
      Enum.reduce(0..(cols - 1), {%{}, []}, fn c, {cells, passes} ->
        %{kind: kind, speed: speed, phase: phase} = elem(state.lanes, c)
        u = phase + t * speed
        {k, from} = advance(c, kind, u, elem(state.passes, c))
        head = JSMath.floor(u - from)
        len = len(c, k, kind)
        {column(cells, c, k, head, len, kind, t, tick), [{k, from} | passes]}
      end)

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(cells, c + r * cols, " ")
      end

    state = %{state | passes: passes |> Enum.reverse() |> List.to_tuple()}
    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp column(cells, c, k, head, len, kind, t, tick) do
    Enum.reduce_while(0..(len - 1)//1, cells, fn d, cells ->
      r = head - d

      cond do
        r < 0 -> {:halt, cells}
        r >= @meta.rows -> {:cont, cells}
        true -> {:cont, glyph(cells, c, r, d, k, len, kind, t, tick)}
      end
    end)
  end

  defp glyph(cells, c, r, d, k, len, kind, t, tick) do
    f = d / len

    glyphs =
      if kind.near? do
        # The first half of a tail is solid; past it more and more drops out.
        cond do
          f > 0.5 and hash(c, r, k * 31 + 7) < :math.pow((f - 0.5) / 0.5, 2) * 0.8 -> nil
          d == 0 -> @head
          d < 3 -> @collar
          f < 0.5 -> @body
          f < 0.7 -> elem(@thin, 0)
          f < 0.86 -> elem(@thin, 1)
          true -> elem(@thin, 2)
        end
      else
        cond do
          f > 0.7 and hash(c, r, k * 31 + 7) < (f - 0.7) * 2 -> nil
          d == 0 -> elem(@far_sets, 0)
          f < 0.45 -> elem(@far_sets, 1)
          f < 0.8 -> elem(@far_sets, 2)
          true -> elem(@far_sets, 3)
        end
      end

    if glyphs do
      # Heads flicker every frame; tail glyphs change now and then.
      when_ =
        if d == 0,
          do: tick,
          else: JSMath.floor((t + hash(c, r, 5) * 9) * (0.4 + hash(c, r, 6) * 1.6))

      i = JSMath.floor(hash(c, r, when_) * byte_size(glyphs))
      Map.put(cells, c + r * @meta.cols, binary_part(glyphs, i, 1))
    else
      cells
    end
  end
end
