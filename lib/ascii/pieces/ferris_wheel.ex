defmodule Ascii.Pieces.FerrisWheel do
  @moduledoc """
  A wheel turning on its a-frame, cabins hanging upright.

  A wheel of eight spokes turning slowly on a braced A-frame, its cabins
  hanging upright from the rim and passing the boarding deck.

  Ported from `src/pieces/ferris-wheel.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "ferris wheel",
    category: :objects,
    note: "a wheel turning on its a-frame, cabins hanging upright",
    cols: 64,
    rows: 26,
    fps: 10
  }

  @cols 64
  @rows 26
  # Spokes, one cabin at the end of each; the rim's radius in rows; seconds
  # per revolution; lights round the rim.
  @n 8
  @r 10
  @turn 30
  @bulbs 24
  # The hub, in cells.
  @cx 32.5
  @cy 11.5
  @ground @rows - 1

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options), do: %{rim: rim(), frame: a_frame()}

  # The rim, traced once: each cell it crosses gets the glyph for the slope
  # and height of the arc inside it, and its upright sides take one cell a
  # row. Upstream keeps the cells in a Map, so they are kept here in the
  # order they were first set.
  defp rim do
    side = @r * 0.3

    sides =
      for r <-
            Stream.iterate(JSMath.ceil(@cy - side - 0.5), &(&1 + 1))
            |> Enum.take_while(&(&1 + 0.5 < @cy + side)),
          d = r + 0.5 - @cy,
          w = 2 * :math.sqrt(@r * @r - d * d),
          c <- [@cx - w, @cx + w],
          do: r * @cols + floor(c)

    acc =
      Enum.reduce(sides, {%{}, []}, fn k, {map, order} ->
        {Map.put(map, k, {1, 0.5, 1, 0}), if(Map.has_key?(map, k), do: order, else: [k | order])}
      end)

    {map, order} =
      Enum.reduce(0..1999, acc, fn i, {map, order} = acc ->
        p = i / 2000 * 2 * :math.pi()
        cos = :math.cos(p)
        sin = :math.sin(p)
        x = @cx + 2 * @r * cos
        y = @cy + @r * sin

        if abs(floor(y) + 0.5 - @cy) < side do
          acc
        else
          k = floor(y) * @cols + floor(x)
          {n, fy, fc, fall} = Map.get(map, k, {0, 0, 0, 0})

          e =
            {n + 1, fy + (y - floor(y)), fc + abs(cos), fall + if(sin * cos < 0, do: 1, else: 0)}

          {Map.put(map, k, e), if(Map.has_key?(map, k), do: order, else: [k | order])}
        end
      end)

    order = Enum.reverse(order)

    # Only the fullest slanted cell on each row and side keeps its slant.
    most =
      Enum.reduce(order, %{}, fn k, most ->
        {n, _, _, _} = e = Map.fetch!(map, k)
        phi = phi(e)
        # A row and side with no cell yet holds none.
        held =
          case Map.fetch(most, id(k)) do
            {:ok, j} -> elem(Map.fetch!(map, j), 0)
            :error -> 0
          end

        if phi > 50 and phi <= 72 and n > held, do: Map.put(most, id(k), k), else: most
      end)

    for k <- order do
      {n, fy, _, fall} = e = Map.fetch!(map, k)
      {k, rim_glyph(phi(e), Map.get(most, id(k)) == k, fall / n, fy / n)}
    end
  end

  defp phi({n, _, c, _}) do
    q = c / n
    :math.atan2(q, :math.sqrt(max(0, 1 - q * q))) * 180 / :math.pi()
  end

  defp id(k), do: div(k, @cols) * 2 + if(rem(k, @cols) < @cx, do: 0, else: 1)

  defp rim_glyph(phi, _most, _fall, _fy) when phi > 72, do: "|"
  defp rim_glyph(_phi, true, fall, _fy), do: if(fall > 0.5, do: "\\", else: "/")
  defp rim_glyph(_phi, false, _fall, fy) when fy < 0.38, do: "'"
  defp rim_glyph(phi, false, _fall, fy) when fy > 0.62, do: if(phi > 10, do: ".", else: "_")
  defp rim_glyph(_phi, false, _fall, _fy), do: "-"

  # The A-frame: a pair of legs a side running from the axle down to the
  # ground, one cell a row, with rungs between each pair. Later writes win,
  # as in upstream's Map.
  defp a_frame do
    top = JSMath.ceil(@cy)
    slope = 0.9

    for s <- [-1, 1], r <- top..(@ground - 1)//1, reduce: %{} do
      frame ->
        d = 1.2 + slope * (r - top)
        a = floor(@cx + s * d)
        b = floor(@cx + s * (d + 2.6))
        leg = if s < 0, do: "/", else: "\\"
        frame = frame |> Map.put(r * @cols + a, leg) |> Map.put(r * @cols + b, leg)

        if rem(r - top, 3) == 2,
          do:
            Enum.reduce(
              (min(a, b) + 1)..(max(a, b) - 1)//1,
              frame,
              &Map.put(&2, r * @cols + &1, "─")
            ),
          else: frame
    end
  end

  defp put(out, c, r, g) do
    c = floor(c)
    r = floor(r)

    if c >= 0 and c < @cols and r >= 0 and r < @rows,
      do: Map.put(out, r * @cols + c, g),
      else: out
  end

  defp text(out, c, r, s) do
    s
    |> String.codepoints()
    |> Enum.with_index()
    |> Enum.reduce(out, fn
      {" ", _}, out -> out
      {g, i}, out -> put(out, c + i, r, g)
    end)
  end

  @impl true
  def frame(state, t, _env) do
    a = 2 * :math.pi() * t / @turn

    # Spokes, dotted from the hub to just short of the rim.
    {out, ends} =
      Enum.reduce(0..(@n - 1), {%{}, []}, fn k, {out, ends} ->
        th = a + k * 2 * :math.pi() / @n
        cos = :math.cos(th)
        sin = :math.sin(th)
        x = @cx + 2 * @r * cos
        y = @cy + @r * sin

        out =
          Enum.reduce(3..(2 * @r - 2), out, fn i, out ->
            put(out, @cx + i * cos, @cy + i / 2 * sin, "·")
          end)

        {out, [{x, y} | ends]}
      end)

    out = Enum.reduce(state.rim, out, fn {k, g}, out -> Map.put(out, k, g) end)

    # Bulbs on the rim between the cabins, every other one lit in turn.
    blink = rem(JSMath.floor(t / 0.6), 2)

    out =
      for k <- 0..(@bulbs - 1),
          rem(k, div(@bulbs, @n)) != 0,
          rem(k + blink, 2) != 0,
          reduce: out do
        out ->
          th = a + k * 2 * :math.pi() / @bulbs + :math.pi() / @bulbs
          put(out, @cx + 2 * @r * :math.cos(th), @cy + @r * :math.sin(th), "*")
      end

    out = Map.merge(out, state.frame)
    out = text(out, @cx - 1.5, @cy, "(@)")

    # Cabins hang from each spoke end, always upright.
    out =
      ends
      |> Enum.reverse()
      |> Enum.reduce(out, fn {x, y}, out ->
        c = floor(x)
        r = floor(y)

        out
        |> put(c, r, "o")
        |> text(c - 2, r + 1, "╭─┴─╮")
        |> text(c - 2, r + 2, "╰───╯")
      end)

    # The boarding deck under the lowest cabin, and the ground.
    out = text(out, @cx - 7.5, @ground - 1, String.duplicate("▄", 15))
    out = Enum.reduce(0..(@cols - 1), out, &put(&2, &1, @ground, "▀"))

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
