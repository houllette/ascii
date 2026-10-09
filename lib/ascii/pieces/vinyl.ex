defmodule Ascii.Pieces.Vinyl do
  @moduledoc """
  A record turning under the tonearm, seen from above.

  A record turning on a turntable, seen from above. The label and a few
  specks of dust turn at 33 1/3 rpm, the sheen on the grooves stays put, and
  a J-shaped tonearm rests in the outer grooves.

  Only the label and the dust move, so everything else is drawn once in
  `init/1`, for ink and for paper.

  Ported from `src/pieces/vinyl.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "vinyl",
    category: :objects,
    note: "a record turning under the tonearm, seen from above",
    cols: 64,
    rows: 25,
    fps: 24,
    loop: 9
  }

  @cols 64
  @rows 25
  @ramp {" ", ".", "·", ":", "-", "=", "+", "*", "#", "%", "@"}
  # 33 1/3 rpm, in radians per second.
  @spin 2 * :math.pi() * 100 / 3 / 60
  # The record, in rows; the platter's edge; the label.
  @r 9
  @rim 9.9
  @label 4
  # The smooth bands between tracks.
  @gaps [6.2, 7.5]
  # Radius, angle.
  @dust [{6.8, 0.4}, {8.2, 2.9}, {5.4, 4.4}]
  # The spindle, in cells.
  @cx 22.5
  @cy 12.5

  @impl true
  def meta, do: @meta

  # The label's print, in its own frame (rows, x across): a title band above
  # the spindle and a round mark off to one side below it. The squared
  # distance settles all but the closest calls, which take Math.hypot.
  defp printed?(x, y) when y > -2.9 and y < -1.45 and abs(x) < 2.7, do: true

  defp printed?(x, y) do
    a = x - 1.5
    b = y - 1.9
    q = a * a + b * b

    cond do
      q < 0.5625 * 0.999999 -> true
      q > 0.5625 * 1.000001 -> false
      true -> JSMath.hypot(a, b) < 0.75
    end
  end

  @impl true
  def init(_options) do
    {cells, labels} = cells()
    edge = edge()

    base = fn paper ->
      Enum.reduce(cells, Map.new(edge), fn {k, b}, out ->
        Map.put(out, k, ramp(b, paper))
      end)
    end

    %{base: {base.(false), base.(true)}, labels: labels, overlay: overlay()}
  end

  defp ramp(b, false), do: elem(@ramp, b)
  defp ramp(b, true), do: elem(@ramp, tuple_size(@ramp) - 1 - b)

  # Per cell: radius in rows, angle, and the cell's radial depth, so a ring
  # drawn within half of it is one cell thick all the way round. Label cells
  # keep sixteen sample points so the print keeps its shape as it turns.
  # Everything off the label is shaded once, by the sheen.
  defp cells do
    shaded =
      for r <- 0..(@rows - 1),
          c <- 0..(@cols - 1),
          dx = (c + 0.5 - @cx) / 2,
          dy = r + 0.5 - @cy,
          d = JSMath.hypot(dx, dy),
          d <= @r + 0.1 and d >= 0.6 do
        th = :math.atan2(dy, dx)
        h = 0.5 * abs(:math.cos(th)) + abs(:math.sin(th))
        s = sheen(th)
        k = r * @cols + c

        cond do
          d < @label ->
            {:label, k, for(j <- 0..3, i <- 0..3, do: {dx + (i - 1.5) / 8, dy + (j - 1.5) / 4})}

          d > @r - 0.45 ->
            {k, 4 + JSMath.round(2 * s)}

          d < @label + 1 ->
            {k, 2 + JSMath.round(2 * s)}

          Enum.any?(@gaps, &(abs(d - &1) < h / 2)) ->
            {k, 2 + JSMath.round(3 * s)}

          true ->
            {k, 3 + JSMath.round(4 * s)}
        end
      end

    {for({k, b} <- shaded, do: {k, b}), for({:label, k, sub} <- shaded, do: {k, sub})}
  end

  # Light bars: two opposite wedges where the grooves catch a lamp to the
  # upper left. They stay put while the record turns under them.
  defp sheen(th) do
    d = JSMath.mod(JSMath.mod(th + 0.8, :math.pi()) + :math.pi(), :math.pi()) - :math.pi() / 2
    q = d * 2.4
    :math.exp(-(q * q))
  end

  # The platter's edge, traced once as an outline, each cell taking the
  # glyph for the slope and height of the curve inside it. Its upright sides
  # take one cell a row, and so does each slant. Upstream's Map keeps its
  # cells in the order they were first set, and so does this.
  defp edge do
    side = @rim * 0.3

    sides =
      for r <-
            Stream.iterate(JSMath.ceil(@cy - side - 0.5), &(&1 + 1))
            |> Enum.take_while(&(&1 + 0.5 < @cy + side)),
          q = r + 0.5 - @cy,
          w = 2 * :math.sqrt(@rim * @rim - q * q),
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
        x = @cx + 2 * @rim * cos
        y = @cy + @rim * sin

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

    # The fullest slanted cell on each row and side.
    most =
      Enum.reduce(order, %{}, fn k, most ->
        {n, _, _, _} = e = Map.fetch!(map, k)
        phi = phi(e)

        held =
          case Map.fetch(most, id(k)) do
            {:ok, j} -> elem(Map.fetch!(map, j), 0)
            :error -> 0
          end

        if phi > 50 and phi <= 72 and n > held, do: Map.put(most, id(k), k), else: most
      end)

    for k <- order do
      {n, fy, _, fall} = e = Map.fetch!(map, k)
      {k, edge_glyph(phi(e), Map.get(most, id(k)) == k, fall / n, fy / n)}
    end
  end

  defp phi({n, _, c, _}) do
    q = c / n
    :math.atan2(q, :math.sqrt(max(0, 1 - q * q))) * 180 / :math.pi()
  end

  defp id(k), do: div(k, @cols) * 2 + if(rem(k, @cols) < @cx, do: 0, else: 1)

  defp edge_glyph(phi, _slant, _fall, _fy) when phi > 72, do: "|"
  defp edge_glyph(_phi, true, fall, _fy), do: if(fall > 0.5, do: "\\", else: "/")
  defp edge_glyph(_phi, false, _fall, fy) when fy < 0.42, do: "'"
  defp edge_glyph(phi, false, _fall, fy) when fy > 0.58, do: if(phi > 10, do: ".", else: "_")
  defp edge_glyph(_phi, false, _fall, _fy), do: "-"

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

  # The plinth, its start and speed buttons, and the pitch slider; the
  # tonearm: counterweight behind the pivot, the pivot in its ring, a tube
  # down and round to the headshell, and the cue lever beside it.
  defp overlay do
    out =
      Enum.reduce(1..(@cols - 2), %{}, fn c, out ->
        out |> put(c, 0, "─") |> put(c, @rows - 1, "─")
      end)

    out =
      Enum.reduce(1..(@rows - 2), out, fn r, out ->
        out |> put(0, r, "│") |> put(@cols - 1, r, "│")
      end)

    out =
      out
      |> put(0, 0, "╭")
      |> put(@cols - 1, 0, "╮")
      |> put(0, @rows - 1, "╰")
      |> put(@cols - 1, @rows - 1, "╯")
      |> text(2, 21, "┌──┐")
      |> text(2, 22, "└──┘")
      |> text(47, 21, "┌┐┌┐")
      |> text(47, 22, "└┘└┘")

    out = Enum.reduce(12..22, out, &put(&2, 59, &1, if(&1 == 17, do: "═", else: "┊")))

    out =
      out
      |> text(49, 2, "▗▄▄▄▖")
      |> text(49, 3, "▝▀█▀▘")
      |> text(48, 4, "╭──╨──╮")
      |> text(48, 5, "│  O  │")
      |> text(48, 6, "╰──╥──╯")

    out = Enum.reduce(7..15, out, &put(&2, 51, &1, "║"))

    out
    |> text(41, 16, "══════════╝")
    |> text(36, 16, "▐███▌")
    |> text(54, 9, "╭╮")
    |> text(54, 10, "││")
    |> text(54, 11, "╰╯")
  end

  @impl true
  def frame(state, t, env) do
    a = @spin * t
    ca = :math.cos(a)
    sa = :math.sin(a)
    out = elem(state.base, if(env.paper, do: 1, else: 0))

    # Turn each sample back into the label's frame and count the print.
    out =
      Enum.reduce(state.labels, out, fn {k, sub}, out ->
        ink = Enum.count(sub, fn {x, y} -> printed?(x * ca + y * sa, y * ca - x * sa) end)
        Map.put(out, k, ramp(if(ink > length(sub) / 2, do: 5, else: 9), env.paper))
      end)

    out = put(out, @cx, @cy, "o")

    # Dust riding round with the record.
    out =
      Enum.reduce(@dust, out, fn {r, p}, out ->
        put(out, @cx + 2 * r * :math.cos(p + a), @cy + r * :math.sin(p + a), "°")
      end)

    out = Map.merge(out, state.overlay)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
