defmodule Ascii.Pieces.Galaxy do
  @moduledoc """
  A tilted spiral galaxy turning, its inner stars the fastest.

  A two-armed spiral seen at a tilt. The arm pattern turns slowly as a whole
  while its stars orbit faster near the core, as in a real disc. It glows on
  empty sky, so on paper it keeps its ramp and prints as a negative.

  Ported from `src/pieces/galaxy.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Rand

  @meta %Ascii.Meta{
    name: "galaxy",
    category: :space,
    note: "a tilted spiral galaxy turning, its inner stars the fastest",
    cols: 64,
    rows: 26,
    fps: 20
  }

  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @tau :math.pi() * 2
  # Disc radius in columns.
  @r 28
  # Cos of the tilt: how round the disc looks.
  @inc 0.78
  # The long axis is turned a little off level.
  @pa -0.14
  # The arms turn as one, slowly (radians per second).
  @pattern 0.1

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    cx = cols / 2
    cy = rows / 2
    rot = {:math.cos(@pa), :math.sin(@pa)}
    {cpa, spa} = rot
    # Log spiral pitch, open enough to read as two arms.
    wind = 1 / :math.tan(0.5)

    # Stars that orbit on their own along the outer disc, on a flat rotation curve.
    {stars, rand} =
      Enum.map_reduce(1..110, Rand.seed(11), fn _, rand ->
        {r, rand} = Rand.next(rand)
        {a, rand} = Rand.next(rand)
        {b, rand} = Rand.next(rand)
        {{0.3 + 0.62 * :math.sqrt(r), a * @tau, 0.2 + 0.2 * b}, rand}
      end)

    # Background stars, one to each patch of a 6 by 4 grid that falls clear
    # of the disc, and never on the frame's outer row or column.
    {bg, _} =
      for gy <- 0..3, gx <- 0..5, reduce: {[], rand} do
        {bg, rand} -> patch(gx, gy, cx, cy, rot, bg, rand)
      end

    cells =
      for r <- 0..(rows - 1), c <- 0..(cols - 1) do
        x = c + 0.5 - cx
        y = (r + 0.25 - cy) * 2
        y2 = (r + 0.75 - cy) * 2
        {point(x, y, rot, wind), point(x, y2, rot, wind)}
      end

    %{
      stars: stars,
      bg: Enum.reverse(bg),
      cells: cells,
      rot: {cpa, spa}
    }
  end

  defp patch(gx, gy, cx, cy, {cpa, spa}, bg, rand) do
    %{cols: cols, rows: rows} = @meta

    Enum.reduce_while(1..6, {bg, rand}, fn _, {bg, rand} ->
      {a, rand} = Rand.next(rand)
      {b, rand} = Rand.next(rand)
      c = 1 + JSMath.floor((gx + a) / 6 * (cols - 2))
      r = 1 + JSMath.floor((gy + b) / 4 * (rows - 2))
      x = c - cx
      y = (r - cy) * 2
      u = (x * cpa + y * spa) / @r
      v = (-x * spa + y * cpa) / (@r * @inc)

      if u * u + v * v < 1.4 do
        {:cont, {bg, rand}}
      else
        {p, rand} = Rand.next(rand)
        {:halt, {[{c + r * cols, if(p < 0.2, do: "+", else: ".")} | bg], rand}}
      end
    end)
  end

  # Brightness at a point on screen, in columns from the centre (y down, rows
  # doubled): everything that does not turn. A point off the disc is dark, and
  # one inside the arms' reach is lit by the bulge and disc alone.
  defp point(x, y, {cpa, spa}, wind) do
    u = (x * cpa + y * spa) / @r
    v = (-x * spa + y * cpa) / (@r * @inc)
    r = JSMath.hypot(u, v)

    if r > 1.1 do
      0
    else
      phi = :math.atan2(v, u)
      # The bulge is a squat ball, so on screen it looks rounder than the disc.
      q = JSMath.hypot(u, v * @inc * 1.4) / 0.17
      bulge = 1.6 * :math.exp(-(q * q))
      disc = 0.15 * :math.exp(-r / 0.3)
      # Arms grow out of the bulge, then dim and thin away to two loose tips.
      s = min(1, max(0, (r - 0.12) / 0.16))

      reach =
        s * s * (3 - 2 * s) * (1.3 - 0.8 * r) * :math.exp(-:math.pow(r / 0.8, 3))

      if reach == 0,
        do: bulge + disc,
        else: {phi, :math.log(r + 1.0e-6) * wind, bulge + disc, reach, min(1, r / 0.3)}
    end
  end

  defp light(lit, _turn) when is_number(lit), do: lit

  defp light({phi, l, base, reach, m}, turn) do
    w = 2 * (phi - turn - l)
    arm = :math.pow(0.5 + 0.5 * :math.cos(w), 3.5)
    # On each arm's inner edge.
    dust = :math.pow(0.5 + 0.5 * :math.cos(w - 1.3), 8)
    (base + arm * reach) * (1 - 0.75 * dust * reach * m)
  end

  @impl true
  def frame(%{cells: cells, rot: {cpa, spa}} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    cx = cols / 2
    cy = rows / 2
    turn = -@pattern * t

    field =
      for {p, p2} <- cells do
        JSMath.fround((light(p, turn) + light(p2, turn)) / 2)
      end
      |> List.to_tuple()

    # Inner stars sweep round faster: angular speed falls off as 1 / r. Each
    # brightens what is already there, so they glint on the arms and leave the
    # dark lanes and the smooth core alone.
    field =
      Enum.reduce(state.stars, field, fn {sr, sa, sb}, field ->
        a = sa - sb * t / (sr + 0.08)
        u = sr * :math.cos(a) * @r
        v = sr * :math.sin(a) * @r * @inc
        x = u * cpa - v * spa
        y = u * spa + v * cpa
        c = JSMath.floor(cx + x)
        r = JSMath.floor(cy + y / 2)

        if c >= 0 and c < cols and r >= 0 and r < rows do
          k = c + r * cols
          put_elem(field, k, JSMath.fround(elem(field, k) * 1.6))
        else
          field
        end
      end)

    last = tuple_size(@ramp) - 1

    out =
      field
      |> Tuple.to_list()
      |> Enum.map(fn
        f when f == 0 -> " "
        f -> elem(@ramp, min(last, JSMath.floor((1 - :math.exp(-1.8 * f)) * 10)))
      end)
      |> List.to_tuple()

    out =
      Enum.reduce(state.bg, out, fn {k, ch}, out ->
        if elem(out, k) == " ", do: put_elem(out, k, ch), else: out
      end)

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: elem(out, r * cols + c)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
