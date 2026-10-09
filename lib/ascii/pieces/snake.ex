defmodule Ascii.Pieces.Snake do
  @moduledoc """
  A snake slithering along an s-curve, flicking its tongue.

  A diamondback seen from above, sliding along its own S-shaped track and
  flicking its tongue. It leaves the right edge and comes back on the left.

  Ported from `src/pieces/snake.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Ramp, Text}

  @meta %Ascii.Meta{
    name: "snake",
    category: :creatures,
    note: "a snake slithering along an s-curve, flicking its tongue",
    cols: 64,
    rows: 15,
    fps: 20
  }

  @cols 64
  @rows 15
  @ramp Ramp.new(" .:-=+*#%@")
  @ramp_n tuple_size(@ramp)
  # The world wraps at the frame's width.
  @w 64
  # The track: wavelength, height, middle row.
  @lambda 32
  @amp 3.5
  @mid 7
  # Body length behind the snout, in columns.
  @len 44
  # Columns a second, so a lap is ten seconds.
  @speed 6.4
  @k 2 * :math.pi() / @lambda
  # The head, snout to the right, on rows -2 to 1 about its middle row. It
  # stays level and the neck bends to meet it; eyes either side of the midline.
  @head [
    "  ___      ",
    "-'  o`--._ ",
    "==::=====:>",
    "-.__o.--'' "
  ]
  # Columns from the back of the head to the snout.
  @hl 11
  # Columns of neck over which the body eases onto the track.
  @neck 9
  # The last columns of the tail, drawn as a single thread.
  @tip 6

  @impl true
  def meta, do: @meta

  @compile {:inline, ease: 1, track_y: 1, wrap: 1}
  defp ease(x) when x <= 0, do: 0
  defp ease(x) when x >= 1, do: 1
  defp ease(x), do: x * x * (3 - 2 * x)

  defp track_y(x), do: @mid + @amp * :math.sin(@k * x)

  defp wrap(x), do: JSMath.mod(JSMath.mod(x, @w) + @w, @w)

  # Half the body's thickness, in half rows, by distance behind the snout: a
  # neck as wide as the back of the head, a thick middle and a long taper.
  defp girth(d) when d < @hl + 4, do: 2.1

  defp girth(d) do
    f = d / @len

    if f < 0.45,
      do: 2.1 + 0.9 * :math.sin((d - @hl - 4) / (0.45 * @len - @hl - 4) * (:math.pi() / 2)),
      else: 3 * max(0, 1 - :math.pow((f - 0.45) / 0.55, 1.3))
  end

  @impl true
  def init(_options) do
    head =
      for {l, j} <- Enum.with_index(@head) do
        chars = Text.chars(l)
        a = Enum.find_index(chars, &(&1 != " "))
        b = l |> String.trim_trailing() |> Text.length()
        for {ch, i} <- Enum.with_index(chars), i >= a and i < b, do: {i, j, ch}
      end

    %{
      head: List.flatten(head),
      # Each cell's three sample columns across, and its four sample rows down.
      across: for(i <- 0..2, do: (i + 0.5) / 3),
      down: for(j <- 0..3, do: {(j + 0.5) / 4, 1.5 - j})
    }
  end

  @impl true
  def frame(state, t, env) do
    head = wrap(t * @speed + 50)
    tip = JSMath.floor(head)
    # The head sits on whole rows where the track meets the back of it.
    r0 = JSMath.round(track_y(tip - @hl + 0.5) - 0.5)
    ink = &elem(@ramp, if(env.paper, do: @ramp_n - &1, else: &1))

    # The middle sample column, c + 1.5 / 3, is exactly the cell's middle,
    # c + 0.5, where the shading samples.
    cols =
      for c <- 0..(@cols - 1) do
        [a, b, e] = for o <- state.across, do: column(c + o, tip, r0)
        {a, b, e, wrap(tip + 1 - (c + 0.5))}
      end

    out =
      Enum.reduce(0..(@rows - 1), %{}, fn r, out ->
        ys = for {o, wy} <- state.down, do: {r + o, wy}
        row(out, r, cols, ys, ink)
      end)

    out =
      out
      |> tail(tip, r0)
      |> head(state.head, tip, r0, ink)
      |> tongue(t, tip, r0)

    lines =
      for r <- 0..(@rows - 1) do
        base = r * @cols
        for c <- 0..(@cols - 1), do: Map.get(out, base + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # The body's middle line, by distance behind the snout: level at the head,
  # easing onto the track down the neck.
  defp mid_y(d, tip, r0) do
    x = tip + 1 - d
    m = ease((d - @hl) / @neck)
    r0 + 0.5 + (track_y(x) - r0 - 0.5) * m
  end

  # What across(x, y) needs of a column x: the middle line, the slope's
  # stretch and the girth there, or nil where x is off the body (across is 2).
  defp column(x, tip, r0) do
    d = wrap(tip + 1 - x)

    if d < @hl - 1 or d >= @len - @tip do
      nil
    else
      g = girth(d)

      if g < 0.05 do
        nil
      else
        # Slope in half rows a column.
        s = (mid_y(d - 0.5, tip, r0) - mid_y(d + 0.5, tip, r0)) * 2
        {mid_y(d, tip, r0), JSMath.hypot(1, s), g}
      end
    end
  end

  # How far across the body (x, y) is, as a share of its half width; 2 off it.
  @compile {:inline, across: 2}
  defp across(nil, _y), do: 2
  defp across({mid, hyp, g}, y), do: (y - mid) * 2 / hyp / g

  defp row(out, r, cols, ys, ink) do
    {out, _} =
      Enum.reduce(cols, {out, r * @cols}, fn {a, b, e, d}, {out, k} ->
        {n, sx, sy} =
          Enum.reduce(ys, {0, 0, 0}, fn {y, wy}, acc ->
            acc |> hit(a, y, -1, wy) |> hit(b, y, 0, wy) |> hit(e, y, 1, wy)
          end)

        {cell(out, k, n, sx, sy, d, b, r, ink), k + 1}
      end)

    out
  end

  defp hit({n, sx, sy} = acc, col, y, di, wy) do
    if abs(across(col, y)) < 1, do: {n + 1, sx + di, sy + wy}, else: acc
  end

  defp cell(out, _k, 0, _sx, _sy, _d, _m, _r, _ink), do: out

  # An edge cell: the outline, facing the way the body lies.
  defp cell(out, k, n, sx, sy, _d, _m, _r, _ink) when n < 7,
    do: Map.put(out, k, edge(n, sx / n, sy / n))

  # A chain of diamonds down an even back, the flanks a shade lighter;
  # towards the tail the pattern gives out.
  defp cell(out, k, _n, _sx, _sy, d, m, r, ink) do
    v = abs(across(m, r + 0.5))

    ch =
      cond do
        v < 0.4 and d < 0.8 * @len -> if rem(JSMath.floor(d), 2) == 1, do: "<", else: ">"
        v > 0.62 or d > 0.88 * @len -> ink.(2)
        true -> ink.(4)
      end

    Map.put(out, k, ch)
  end

  defp edge(n, ux, uy) do
    cond do
      abs(uy) > abs(ux) * 1.2 and uy < 0 -> if n < 4, do: "_", else: "-"
      abs(uy) > abs(ux) * 1.2 -> if n < 4, do: "'", else: "-"
      abs(ux) > abs(uy) * 2 -> if ux > 0, do: "(", else: ")"
      ux * uy < 0 -> "/"
      true -> "\\"
    end
  end

  defp put(out, c, r, ch) when r >= 0 and r < @rows,
    do: Map.put(out, r * @cols + Integer.mod(c, @cols), ch)

  defp put(out, _c, _r, _ch), do: out

  # The tip of the tail as a thread: one glyph a row where it is steep and
  # one a column where it is not, each nearest the middle of its slot.
  defp tail(out, tip, r0) do
    {order, slots} = slots(@len - @tip, tip, r0, [], %{})

    order
    |> Enum.reverse()
    |> Enum.reduce(out, fn key, out ->
      {_off, x, y, s, steep} = Map.fetch!(slots, key)
      r = JSMath.floor(y)
      put(out, JSMath.floor(x), r, thread(steep, s, y - r))
    end)
  end

  # d steps by 0.05 from LEN - TIP, adding as upstream adds; the slots keep
  # the order they were first filled in.
  defp slots(d, _tip, _r0, order, slots) when d >= @len, do: {order, slots}

  defp slots(d, tip, r0, order, slots) do
    x = tip + 1 - d
    y = mid_y(d, tip, r0)
    s = (mid_y(d - 0.05, tip, r0) - mid_y(d + 0.05, tip, r0)) * 20
    steep = abs(s) > 1.2
    key = if steep, do: {:r, JSMath.floor(y)}, else: {:c, JSMath.floor(x)}

    off =
      if steep,
        do: abs(y - JSMath.floor(y) - 0.5),
        else: abs(x - JSMath.floor(x) - 0.5)

    case slots do
      %{^key => {best, _, _, _, _}} when off >= best ->
        slots(d + 0.05, tip, r0, order, slots)

      %{^key => _} ->
        slots(d + 0.05, tip, r0, order, Map.put(slots, key, {off, x, y, s, steep}))

      _ ->
        slots(d + 0.05, tip, r0, [key | order], Map.put(slots, key, {off, x, y, s, steep}))
    end
  end

  # s > 0 runs down to the right.
  defp thread(true, s, _f), do: if(s > 0, do: "\\", else: "/")
  defp thread(false, s, f) when abs(s) > 0.5 and f < 0.5, do: if(s > 0, do: "`", else: "'")
  defp thread(false, s, _f) when abs(s) > 0.5, do: "."
  defp thread(false, _s, f) when f < 0.3, do: "'"
  defp thread(false, _s, f) when f > 0.7, do: "_"
  defp thread(false, _s, _f), do: "-"

  # The head goes over the neck, blanking whatever body it covers, its
  # scales shaded like the back's.
  defp head(out, head, tip, r0, ink) do
    Enum.reduce(head, out, fn {i, j, ch}, out ->
      ch =
        case ch do
          "=" -> ink.(4)
          ":" -> ink.(2)
          ch -> ch
        end

      put(out, tip - @hl + 1 + i, r0 - 2 + j, ch)
    end)
  end

  # The forked tongue leaves the snout's tip, flicking out twice.
  defp tongue(out, t, tip, r0) do
    fl = JSMath.mod(t, 2.2)

    len =
      cond do
        fl > 0.2 and fl < 0.55 -> 3
        fl > 0.75 and fl < 1 -> 2
        true -> 0
      end

    Enum.reduce(1..len//1, out, fn i, out ->
      put(out, tip + i, r0, if(i == len, do: "<", else: "-"))
    end)
  end
end
