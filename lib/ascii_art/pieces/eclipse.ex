defmodule AsciiArt.Pieces.Eclipse do
  @moduledoc """
  The moon slides over the sun; diamond ring, then corona.

  A total solar eclipse. The new moon slides across the sun; the last bead of
  sunlight flares into a diamond ring, the corona opens round the black disk
  for totality, and the ring flashes again on the far side.

  Ported from `src/pieces/eclipse.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Rand

  @meta %AsciiArt.Meta{
    name: "eclipse",
    category: :space,
    note: "the moon slides over the sun; diamond ring, then corona",
    cols: 64,
    rows: 27,
    fps: 20
  }

  # The sun and corona are light, not shade, so the ramp keeps its sense on
  # paper: there the sun is a disk of ink and the corona a halo of it.
  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @n 9
  # The sun's radius in rows; it spans twice as many columns.
  @r 6
  # The moon's radius, in suns.
  @moon 1.06
  # Seconds from one crossing to the next; the middle of totality, in seconds
  # from t = 0.
  @loop 18
  @mid 5.3
  # The moon's path, radians below level, and how far off centre it passes,
  # in suns.
  @tilt 0.2
  @miss 0.005
  # Samples per cell each way for the sun's edge.
  @ss 3
  @samples @ss * @ss

  # Streamers: angle, width at the limb in radians, how fast they fade
  # outward in suns, and strength. They narrow as they go, so each ends in a
  # point.
  @streamers [
    {0.1, 0.42, 0.44, 0.85},
    {3.28, 0.45, 0.44, 0.8},
    {0.85, 0.15, 0.5, 0.6},
    {2.35, 0.16, 0.48, 0.6},
    {-0.6, 0.15, 0.45, 0.55},
    {3.9, 0.14, 0.42, 0.5}
  ]
  # Prominences: angle and size, small loops of gas just off the limb that the
  # moon covers and uncovers as it passes.
  @proms [{2.9, 0.06}, {-0.9, 0.05}, {0.5, 0.04}]

  # Squared distances from the moon's centre past which a whole cell is clear
  # of the limb's band, outside or inside (a sample is within 0.07 of its
  # cell's centre), and the same for one sample. Between them the distance is
  # taken exactly, as upstream takes it.
  @cell_out 1.19 * 1.19
  @cell_in 0.94 * 0.94
  @sample_out 1.2
  @sample_in 1.0

  @compile {:inline, smooth: 3}

  @impl true
  def meta, do: @meta

  defp x_of(c), do: (c - @meta.cols / 2) / (2 * @r)
  defp y_of(r), do: (@meta.rows / 2 - r) / @r

  defp smooth(a, b, x) do
    u = min(1, max(0, (x - a) / (b - a)))
    u * u * (3 - 2 * u)
  end

  defp wrap(a), do: :math.atan2(:math.sin(a), :math.cos(a))

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta

    # The moon's limb is ragged with valleys and peaks: Baily's beads.
    {limb, rand} =
      Enum.map_reduce(0..4, Rand.seed(11), fn k, rand ->
        {a, rand} = Rand.next(rand)
        {b, rand} = Rand.next(rand)
        {{3 + 4 * k + JSMath.floor(a * 3), b * 6.283, 0.006 / (1 + k * 0.4)}, rand}
      end)

    # The corona's shape never changes, only how much of it shows: a bright
    # inner ring, a soft halo, the streamers and fine plumes at the poles.
    {cells, _} =
      Enum.map_reduce(0..(rows * cols - 1), rand, fn k, rand ->
        cell(div(k, cols), rem(k, cols), rand)
      end)

    # A planet.
    planet = 2 * cols + JSMath.round(cols / 2 - 2.4 * 2 * @r)
    cells = List.update_at(cells, planet, &%{&1 | star: 2})

    %{limb: limb, cells: cells}
  end

  defp cell(r, c, rand) do
    x = x_of(c + 0.5)
    y = y_of(r + 0.5)
    d = JSMath.hypot(x, y)
    a = :math.atan2(y, x)
    {corona, ring, star, rand} = corona(x, y, d, a, rand)

    samples =
      for j <- 0..(@ss - 1), i <- 0..(@ss - 1) do
        sx = x_of(c + (i + 0.5) / @ss)
        sy = y_of(r + (j + 0.5) / @ss)
        q = 1 - sx * sx - sy * sy
        {sx, sy, if(q > 0, do: 0.72 + 0.28 * :math.sqrt(q))}
      end

    clear = Enum.reduce(samples, 0, fn {_, _, lit}, sum -> if lit, do: sum + lit, else: sum end)

    {%{
       x: x,
       y: y,
       samples: samples,
       clear: level(clear / @samples),
       angle: JSMath.fround(a),
       corona: corona,
       ring: ring,
       sum: corona + ring,
       bound: corona + 1.3 * ring * 1.26,
       star: star
     }, rand}
  end

  defp corona(_x, _y, d, _a, rand) when d < 1, do: {0.0, 0.0, 0, rand}

  defp corona(x, y, d, a, rand) do
    dp = :math.pow(d, 1.7)

    s =
      Enum.reduce(@streamers, 0, fn {at, w, fall, amp}, s ->
        off = wrap(a - at) / (w / dp)
        s + amp * :math.exp(-off * off) * :math.exp(-(d - 1) / fall)
      end)

    p = (abs(a) - :math.pi() / 2) / 0.4
    pole = :math.exp(-(p * p)) * (0.5 + 0.5 * :math.cos(26 * a))

    ring =
      Enum.reduce(@proms, JSMath.fround(:math.exp(-(d - 1) / 0.07)), fn {at, size}, ring ->
        px = :math.cos(at) * (1 + size)
        py = :math.sin(at) * (1 + size)
        u = (x - px) / size
        v = (y - py) / (size * 0.8)
        JSMath.fround(ring + 1.4 * :math.exp(-(u * u + v * v)))
      end)

    corona =
      JSMath.fround(
        0.25 * :math.exp(-(d - 1) / 0.16) + s + 0.3 * pole * :math.exp(-(d - 1) / 0.2)
      )

    if d > 1.7 and corona < 0.02 do
      {u, rand} = Rand.next(rand)
      {corona, ring, if(u < 0.014, do: 1, else: 0), rand}
    else
      {corona, ring, 0, rand}
    end
  end

  # The ramp index for the sunlight a cell gets.
  defp level(lit) when lit > 0, do: JSMath.round(max(:math.pow(lit, 0.7), 0.2) * @n)
  defp level(_lit), do: 0

  @impl true
  def frame(%{limb: limb, cells: cells} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    tau = JSMath.mod(JSMath.mod(t - @mid + @loop / 2, @loop) + @loop, @loop) - @loop / 2
    # Slow near the middle, fast at the ends.
    d = 0.035 * tau + 0.00515 * :math.pow(tau, 3)
    mx = d * :math.cos(@tilt) + @miss * :math.sin(@tilt)
    my = -d * :math.sin(@tilt) + @miss * :math.cos(@tilt)
    off = JSMath.hypot(mx, my)
    # The widest sliver of sun left, in suns; below 0 is totality.
    gap = off + 1 - @moon
    # The corona shows as the sunlight goes.
    show = 1 - smooth(0, 0.07, gap)
    flare = smooth(0, -0.03, gap)
    bead = smooth(-0.004, 0.01, gap) * (1 - smooth(0.04, 0.09, gap))
    # The corona brightens as the eyes adapt through totality.
    glow = 0.75 + 0.45 * smooth(0, -0.055, gap)

    sky = %{t: t, mx: mx, my: my, show: show, flare: flare, glow: glow, limb: limb}
    out = cells |> Enum.map(&cell_char(&1, sky)) |> List.to_tuple()
    out = if bead > 0.05, do: diamond(out, bead, mx / off, my / off), else: out

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: elem(out, r * cols + c)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cell_char(cell, sky) do
    {moon, i} = sunlight(cell, sky)
    i = corona_level(cell, sky, moon, i)

    cond do
      i == 0 and cell.star != 0 and sky.flare > 0.4 -> if cell.star == 2, do: "*", else: "."
      # Before totality the moon's rim shows faintly against the sky.
      i == 0 and moon > 0 and moon < @samples and sky.show < 0.5 -> "."
      true -> elem(@ramp, i)
    end
  end

  # How many of a cell's samples the moon covers, and the sunlight's ramp
  # index from the rest.
  defp sunlight(%{x: x, y: y} = cell, %{mx: mx, my: my} = sky) do
    dx = x - mx
    dy = y - my
    dd = dx * dx + dy * dy

    cond do
      dd > @cell_out ->
        {0, cell.clear}

      dd < @cell_in ->
        {@samples, 0}

      true ->
        {moon, lit} =
          Enum.reduce(cell.samples, {0, 0}, fn {sx, sy, contrib}, {moon, lit} ->
            cond do
              in_moon?(sx - mx, sy - my, sky.limb) -> {moon + 1, lit}
              contrib -> {moon, lit + contrib}
              true -> {moon, lit}
            end
          end)

        {moon, level(lit / @samples)}
    end
  end

  defp in_moon?(dx, dy, limb) do
    dd = dx * dx + dy * dy

    cond do
      dd > @sample_out ->
        false

      dd < @sample_in ->
        true

      true ->
        dm = JSMath.hypot(dx, dy)
        dm < @moon + 0.02 and (dm < @moon - 0.02 or dm < moon_r(:math.atan2(dy, dx), limb))
    end
  end

  defp moon_r(a, limb),
    do: @moon + Enum.reduce(limb, 0, fn {k, p, h}, s -> s + h * :math.sin(k * a + p) end)

  # The corona lifts a cell the moon leaves partly open. Where it could not
  # reach the next level even at its brightest shimmer (pow(0.05, 0.8) * 9 +
  # 0.1 < 1), or the cell is already full, upstream's max keeps i.
  defp corona_level(%{sum: sum}, _sky, moon, i) when moon >= @samples or sum <= 0 or i >= @n,
    do: i

  defp corona_level(cell, %{show: show, glow: glow} = sky, moon, i) do
    if cell.bound * glow * show < 0.05 do
      i
    else
      a = cell.angle
      shimmer = 1 + 0.25 * :math.sin(9 * a + 1.9 * sky.t) * :math.sin(5 * a - 1.2 * sky.t)
      cv = (cell.corona + 1.3 * cell.ring * shimmer) * glow
      lift = :math.pow(min(1, cv * show), 0.8) * (1 - moon / @samples) * @n + 0.1
      max(i, min(@n, JSMath.floor(lift)))
    end
  end

  # The diamond: one bead of sun on the limb, too bright for its cell, with a
  # short flare either side and above and below.
  defp diamond(out, bead, ux, uy) do
    %{cols: cols, rows: rows} = @meta
    bx = cols / 2 - ux * 2 * @r
    by = rows / 2 + uy * @r

    put = fn out, dc, dr, ch ->
      c = JSMath.floor(bx + dc)
      r = JSMath.floor(by + dr)

      if c >= 0 and c < cols and r >= 0 and r < rows,
        do: put_elem(out, r * cols + c, ch),
        else: out
    end

    arm = if bead > 0.5, do: 2, else: 1

    out =
      Enum.reduce(1..arm, out, fn s, out ->
        ch = if s == arm, do: "-", else: "="
        out |> put.(s, 0, ch) |> put.(-s, 0, ch)
      end)

    out =
      if bead > 0.4 do
        ch = if bead > 0.75, do: "|", else: ":"
        out |> put.(0, -1, ch) |> put.(0, 1, ch)
      else
        out
      end

    put.(out, 0, 0, "@")
  end
end
