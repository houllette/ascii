defmodule AsciiArt.Pieces.Jellyfish do
  @moduledoc """
  A jellyfish pulsing upward, its tentacles trailing late.

  A moon jelly swimming up through dark water. The bell squeezes and
  relaxes, the tentacles follow the rim a beat late, and specks drift by.

  Ported from `src/pieces/jellyfish.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Ramp

  @meta %AsciiArt.Meta{
    name: "jellyfish",
    category: :creatures,
    note: "a jellyfish pulsing upward, its tentacles trailing late",
    cols: 44,
    rows: 26,
    fps: 24
  }

  @cols 44
  @rows 26
  # No "-" inside, so only the outline uses it.
  @ramp Ramp.new(" .::=+*#%@")
  @ramp_n tuple_size(@ramp)
  # Seconds per stroke.
  @p 2.2
  # Share of the stroke spent squeezing.
  @sq 0.28

  # The threads' lag and the longest any of them hangs; the mouth arms'.
  @thread_lag 0.06
  @arm_lag 0.09
  @arm_len 10

  @impl true
  def meta, do: @meta

  @compile {:inline, ease: 1, phase: 1}
  defp ease(x), do: x * x * (3 - 2 * x)

  defp phase(t), do: JSMath.mod(JSMath.mod(t, @p) + @p, @p) / @p

  # 0 relaxed, 1 fully squeezed.
  defp squeeze(t) do
    p = phase(t)
    if p < @sq, do: ease(p / @sq), else: 1 - ease((p - @sq) / (1 - @sq))
  end

  # How far the stroke has carried the body up: it lurches with the squeeze
  # and sinks back.
  defp lift(t) do
    p = phase(t)
    if p < 0.4, do: ease(p / 0.4), else: 1 - ease((p - 0.4) / 0.6)
  end

  # Where the rim sits and how wide it is, given how squeezed the bell is:
  # {c, x, y, half}.
  defp rim_at(t) do
    c = squeeze(t)
    x = @cols / 2 + 1.5 * :math.sin(2 * :math.pi() * t / (5 * @p))
    {c, x, 11 - 0.8 * c - 1.4 * lift(t), (13 - 2.6 * c) * (1 - 0.3 * c)}
  end

  # How far the water has moved past: faster while the bell pushes.
  defp travel(t) do
    k = JSMath.floor(t / @p)
    p = phase(t)

    0.9 * t +
      2.4 * (k + if(p < @sq, do: 0.8 * ease(p / @sq), else: 0.8 + 0.2 * (p - @sq) / (1 - @sq)))
  end

  @impl true
  def init(_options) do
    {specks, _} =
      Enum.map_reduce(1..30, Int32.to_int32(7), fn _, r ->
        {x, r} = Int32.mulberry32(r)
        {y, r} = Int32.mulberry32(r)
        {z, r} = Int32.mulberry32(r)
        {w, r} = Int32.mulberry32(r)
        {{x * @cols, y * @rows, 0.4 + z * 0.6, w * 6.3}, r}
      end)

    # Eight threads, the outer ones shorter, so the tips stagger.
    threads =
      for i <- 0..7 do
        u = -0.92 + 1.84 * i / 7
        {i, u, 8.5 + 3.2 * (1 - abs(u)) + rem(i * 3, 5) * 0.8}
      end

    longest = threads |> Enum.map(&elem(&1, 2)) |> Enum.max()

    %{
      specks: specks,
      threads: threads,
      # Steps of a quarter down a strand, from d = 1, while d < its length.
      thread_steps: steps(longest),
      arm_steps: steps(@arm_len),
      # The bell's sample offsets across and down a cell.
      across: for(i <- 0..2, do: (i + 0.5) / 3),
      down: for(j <- 0..3, do: {(j + 0.5) / 4, (j - 1.5) / 1.5})
    }
  end

  defp steps(len), do: Enum.take_while(0..1000, &(1 + &1 * 0.25 < len)) |> length()

  defp put(g, x, y, ch) do
    x = JSMath.round(x)
    y = JSMath.round(y)
    if x >= 0 and x < @cols and y >= 0 and y < @rows, do: Map.put(g, y * @cols + x, ch), else: g
  end

  @impl true
  def frame(state, t, _env) do
    d = travel(t)

    g =
      Enum.reduce(state.specks, %{}, fn {sx, sy, sz, sw}, g ->
        y = JSMath.floor(JSMath.mod(JSMath.mod(sy + d * sz, @rows) + @rows, @rows))
        put(g, sx + 0.6 * :math.sin(t * 0.5 + sw), y, if(sz > 0.8, do: "·", else: "."))
      end)

    {c, cx, ny, _half} = now = rim_at(t)
    rim = JSMath.floor(ny)

    # Each point down a tentacle hangs from where the rim was a moment ago:
    # {x, y, half} at d = 1 + m / 4, for each step m.
    threads = trails(t, now, rim, @thread_lag, state.thread_steps)
    arms = trails(t, now, rim, @arm_lag, state.arm_steps)

    g =
      state.threads
      |> Enum.reduce(g, fn thread, g -> thread(g, t, rim, threads, thread) end)
      |> arm(t, rim, arms, 0)
      |> arm(t, rim, arms, 1)
      |> bell(state, c, cx, ny, rim)

    lines =
      for r <- 0..(@rows - 1) do
        base = r * @cols
        for x <- 0..(@cols - 1), do: Map.get(g, base + x, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp trails(t, {_c, _x, ny, _half}, rim, lag, n) do
    for m <- 0..(n - 1)//1 do
      d = 1 + m * 0.25
      {_c, wx, wy, whalf} = rim_at(t - d * lag)
      {wx, rim + d + max(0, wy - ny) * 0.8, whalf}
    end
    |> List.to_tuple()
  end

  # A strand traced down from the rim, one mark per row: how far it leans
  # since the last row, and how much that lean changed, which is its bow.
  defp strand(g, rim, len, trails, x_at, mark) do
    px = x_at.(1, elem(trails, 0))

    {g, _, _, _} =
      Enum.reduce_while((rim + 1)..(@rows - 1)//1, {g, 0, px, 0}, fn y, {g, m, px, pdx} ->
        m = advance(trails, m, len, y)
        d = 1 + m * 0.25

        if d >= len do
          {:halt, {g, m, px, pdx}}
        else
          x = x_at.(d, elem(trails, m))
          dx = x - px
          {:cont, {mark.(g, x, y, dx, dx - pdx, d, d / len), m, x, dx}}
        end
      end)

    g
  end

  defp advance(trails, m, len, y) do
    if 1 + m * 0.25 < len and elem(elem(trails, m), 1) < y,
      do: advance(trails, m + 1, len, y),
      else: m
  end

  # A thread is a plain stroke where it hangs straight and bows only where
  # it bends.
  defp thread(g, t, rim, trails, {i, u, len}) do
    x_at = fn d, {x, _y, half} ->
      x + u * half * (1 - 0.01 * d) +
        (0.05 + d * 0.013) * d * :math.sin(d * 0.5 - t * 3 + i * 1.9)
    end

    strand(g, rim, len, trails, x_at, fn g, x, y, dx, bow, _d, f ->
      put(g, x, y, thread_mark(f, dx, bow))
    end)
  end

  defp thread_mark(f, _dx, _bow) when f > 0.9, do: "."
  defp thread_mark(f, _dx, _bow) when f > 0.8, do: ":"
  defp thread_mark(_f, dx, _bow) when dx > 0.6, do: "\\"
  defp thread_mark(_f, dx, _bow) when dx < -0.6, do: "/"
  defp thread_mark(_f, _dx, bow) when bow > 0.22, do: "("
  defp thread_mark(_f, _dx, bow) when bow < -0.22, do: ")"
  defp thread_mark(_f, _dx, _bow), do: "|"

  # Two frilled mouth arms, each one ribbon a cell wide that widens to two
  # where it turns face on.
  defp arm(g, t, rim, trails, i) do
    s = if i == 1, do: 1, else: -1

    x_at = fn d, {x, _y, half} ->
      x + s * 2 * (1 - d * 0.06) * (half / 10) + 0.9 * :math.sin(d * 0.6 - t * 2.2 + i * 2.5)
    end

    strand(g, rim, @arm_len, trails, x_at, fn
      g, x, y, _dx, _bow, _d, f when f > 0.8 ->
        put(g, x, y, if(f > 0.9, do: ".", else: ":"))

      g, x, y, _dx, _bow, d, _f ->
        tw = :math.cos(d * 1.1 + i * 1.3 - t * 1.6)

        cond do
          abs(tw) < 0.35 -> put(g, x, y, ":")
          tw > 0.5 -> g |> put(x, y, ";") |> put(x + s, y, if(s > 0, do: ")", else: "("))
          true -> put(g, x, y, ";")
        end
    end)
  end

  # The bell: a half dome, glassy in the middle and thick at the edges. Ink
  # stands for how much jelly the eye looks through, so it reads the same on
  # paper and the ramp is not flipped.
  defp bell(g, state, c, cx, ny, rim) do
    a = 13 - 2.6 * c
    b = 13 + 2 * c
    width = fn s -> a * :math.sqrt(1 - s * s) * (1 - 0.3 * c * ((1 - s) * (1 - s))) end
    w0 = width.(0)

    g =
      Enum.reduce(0..(@cols - 1), g, fn x, g ->
        u = (x + 0.5 - cx) / w0

        if abs(u) < 1,
          do: Map.put(g, rim * @cols + x, rim_mark(abs(u), x)),
          else: g
      end)

    # Each column's sample offsets from the axis, |X|, left to right.
    xs =
      for x <- 0..(@cols - 1) do
        List.to_tuple(for o <- state.across, do: abs(x + o - cx))
      end

    Enum.reduce(0..(rim - 1)//1, g, fn r, g ->
      # The half width of the dome at each sample row, or nil off it.
      rows =
        for {o, wy} <- state.down do
          s = (ny - (r + o)) * 2 / b
          {if(s >= 0 and s < 1, do: width.(s), else: nil), wy}
        end

      sc = max(0, (ny - r - 0.5) * 2 / b)
      # The middle of the cell, for a cell well inside: below the crown, so s < 1.
      body = {sc, if(sc < 1, do: width.(sc), else: nil)}

      {g, _} =
        Enum.reduce(xs, {g, 0}, fn ax, {g, x} ->
          {bell_cell(g, r, x, ax, rows, body, cx), x + 1}
        end)

      g
    end)
  end

  defp rim_mark(au, _x) when au > 0.93, do: "'"
  defp rim_mark(_au, x) when rem(x, 2) == 1, do: "~"
  defp rim_mark(_au, _x), do: "'"

  defp bell_cell(g, r, x, ax, rows, body, cx) do
    {n, sx, sy} =
      Enum.reduce(rows, {0, 0, 0}, fn
        {nil, _wy}, acc ->
          acc

        {w, wy}, acc ->
          acc
          |> sample(elem(ax, 0) < w, -1, wy)
          |> sample(elem(ax, 1) < w, 0, wy)
          |> sample(elem(ax, 2) < w, 1, wy)
      end)

    cond do
      n == 0 -> g
      n < 10 -> Map.put(g, r * @cols + x, edge(n, sx / n, sy / n))
      true -> Map.put(g, r * @cols + x, shade(x, body, cx))
    end
  end

  defp sample({n, sx, sy}, true, di, wy), do: {n + 1, sx + di, sy + wy}
  defp sample(acc, false, _di, _wy), do: acc

  # An edge cell: draw the outline facing the way the shape lies.
  defp edge(n, ux, uy) do
    cond do
      uy > abs(ux) * 1.2 -> if n < 5, do: "_", else: "-"
      abs(ux) > uy * 1.5 -> if ux > 0, do: "(", else: ")"
      n < 4 -> "."
      ux > 0 -> "/"
      true -> "\\"
    end
  end

  defp shade(x, {s, w}, cx) do
    u = max(-0.999, min(0.999, (x + 0.5 - cx) / w))
    nz = :math.sqrt(1 - u * u) * :math.sqrt(1 - s * s)
    # Four pale horseshoes show through the top, two of them side on.
    ph = :math.asin(u)
    gap = min(abs(ph - 0.6), abs(ph + 0.6))
    ring = max(0, 1 - abs(JSMath.hypot(gap / 0.36, (s - 0.45) / 0.26) - 1) * 3.5)
    # The crown is the thinnest, glassiest part, so the shade fades out up there.
    crown = 1 - 0.6 * ease(max(0, (s - 0.62) / 0.38))
    v = min(1, (0.16 + 0.07 * s + 0.6 * ((1 - nz) * (1 - nz))) * crown + 0.55 * ring)
    elem(@ramp, max(1, JSMath.round(v * (@ramp_n - 1))))
  end
end
