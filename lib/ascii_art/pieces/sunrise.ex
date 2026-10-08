defmodule AsciiArt.Pieces.Sunrise do
  @moduledoc """
  The sun lifting off a sea horizon, its path glittering.

  The sun coming up out of the sea at dawn. The glow along the horizon
  gathers into bands, the sun climbs out of it and sinks back as dusk, and
  its path glitters on the water.

  Ported from `src/pieces/sunrise.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Hash

  @meta %AsciiArt.Meta{
    name: "sunrise",
    category: :nature,
    note: "the sun lifting off a sea horizon, its path glittering",
    cols: 60,
    rows: 20,
    fps: 15
  }

  @cols 60
  @rows 20
  # The sun, its glow and its glints are light, not shade, so they keep
  # their sense on paper and print as a negative, like eclipse. The glow
  # bands, faint to strong.
  @sky {" ", ".", "·", ":", "-", "="}
  # Seconds, from one dawn to the next; the part of the loop the sun is up.
  @loop 48
  @day 0.85
  # The horizon row; the sun's radius, in rows; the sun's highest, in rows
  # above the horizon; the middle of its arc and how far it travels each
  # way; seconds into the loop at t = 0, the sun a third up; the dark rim
  # between the disc and its corona, in rows.
  @hz 12
  @r 2.6
  @top 6.6
  @cx 30
  @wx 8
  @start 2.2
  @gap 0.32
  # Past this, in rows of the disc's scaled distance, no sample in a cell can
  # touch the disc or its rim, with room to spare for rounding.
  @reach @r + @gap + 0.01

  @impl true
  def meta, do: @meta

  @compile {:inline, clamp: 1, smooth: 3}
  defp clamp(v), do: max(0, min(1, v))

  defp smooth(a, b, v) do
    x = clamp((v - a) / (b - a))
    x * x * (3 - 2 * x)
  end

  # Value noise along x for row r, sliding with time.
  defp noise(x, r, z) do
    i = floor(x)
    j = floor(z)
    u = smooth(0, 1, x - i)
    v = smooth(0, 1, z - j)

    (Hash.murmur(i, r, j) * (1 - u) + Hash.murmur(i + 1, r, j) * u) * (1 - v) +
      (Hash.murmur(i, r, j + 1) * (1 - u) + Hash.murmur(i + 1, r, j + 1) * u) * v
  end

  # Where the sun is a fraction s through the loop: up in an arc for the day,
  # then a short dip under the sea, its speed matched where the two meet.
  defp sun(s) when s < @day do
    p = :math.pi() * (s / @day)
    {@cx - @wx * :math.cos(p), -@r + (@top + @r) * :math.sin(p)}
  end

  defp sun(s) do
    q = :math.pi() * ((s - @day) / (1 - @day))
    {@cx + @wx * :math.cos(q), -@r - (@top + @r) * ((1 - @day) / @day) * :math.sin(q)}
  end

  @impl true
  def init(_options) do
    stars =
      for i <- 0..21 do
        {floor(Hash.murmur(i, 1, 7) * @cols), floor(Hash.murmur(i, 2, 7) * 7),
         Hash.murmur(i, 3, 7)}
      end

    %{stars: stars}
  end

  @impl true
  def frame(state, t, _env) do
    u = JSMath.mod(JSMath.mod(t + @start, @loop) + @loop, @loop)
    {sx, h} = sun(u / @loop)

    # The glow is broad and dim before dawn, strongest as the sun breaks the
    # sea, and draws down into tighter bands as it climbs.
    sc = %{
      sx: sx,
      sy: @hz - h,
      glow: 0.72 + 0.28 * smooth(-4, 0, h) - 0.25 * smooth(1, @top, h),
      height: 3.8 - 1.9 * smooth(0, @top, h),
      night: 1 - smooth(-3, 3, h),
      # How much of the disc is above the sea.
      lit: clamp((h + @r) / (2 * @r))
    }

    g =
      for {c, r, p} <- state.stars,
          tw = 0.5 + 0.5 * :math.sin(t * (1.1 + p) + p * 40),
          (0.25 + sc.night) * tw > 0.6 + r * 0.04,
          into: %{} do
        ch =
          cond do
            p < 0.15 -> "+"
            p < 0.55 -> "·"
            true -> "."
          end

        {{r, c}, ch}
      end

    g =
      for r <- 0..(@hz - 1), c <- 0..(@cols - 1), reduce: g do
        g -> sky(g, sc, r, c)
      end

    g = Enum.reduce((@hz + 1)..(@rows - 1), g, &sea(&2, sc, &1, t))

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: if(r == @hz, do: "▔", else: Map.get(g, {r, c}, " "))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp sky(g, sc, r, c) do
    %{sx: sx, sy: sy, lit: lit} = sc

    # The disc, sampled 3 by 4 in the cell so the horizon cuts it flat; a
    # cell at least half covered is sun, and one that comes near it is left
    # dark, so the disc keeps a clean edge.
    {cov, near} = if far?(sx, sy, r, c), do: {0, 0}, else: disc(sx, sy, r, c)

    cond do
      cov >= 6 -> Map.put(g, {r, c}, "@")
      near > 0 and lit > 0 -> g
      true -> glow(g, sc, r, c)
    end
  end

  # Whether every sample in the cell lies clear of the disc and its rim.
  defp far?(sx, sy, r, c) do
    dx = max(0, max(c - sx, sx - (c + 1))) / 2
    dy = max(0, max(r - sy, sy - (r + 1)))
    dx * dx + dy * dy > @reach * @reach
  end

  defp disc(sx, sy, r, c) do
    for i <- 0..3, j <- 0..2, reduce: {0, 0} do
      {cov, near} ->
        yy = r + (i + 0.5) / 4
        e = JSMath.hypot((c + (j + 0.5) / 3 - sx) / 2, yy - sy) - @r
        {if(yy < @hz and e < 0, do: cov + 1, else: cov), if(e < @gap, do: near + 1, else: near)}
    end
  end

  # Outside it, bands that bow up toward the sun, and a soft corona.
  defp glow(g, sc, r, c) do
    %{sx: sx, sy: sy, lit: lit} = sc
    y = r + 0.5
    x = c + 0.5
    d = JSMath.hypot((x - sx) / 2, y - sy) - @r
    q = (x - sx) / 17
    bow = 0.62 + 0.38 * :math.exp(-(q * q))

    v =
      max(
        sc.glow * :math.exp(-(@hz - y) / sc.height) * bow,
        0.42 * lit * :math.exp(-(d - @gap) / 1.5)
      )

    k = min(tuple_size(@sky) - 1, floor(v * tuple_size(@sky)))
    if k > 0, do: Map.put(g, {r, c}, elem(@sky, k)), else: g
  end

  # The sea, in perspective: short close-set dashes out by the horizon,
  # longer and sparser swells nearer, each run slowly lengthening and
  # shrinking. Under the sun its path breaks into glints that come and go.
  defp sea(g, sc, r, t) do
    k = r - @hz

    row = %{
      r: r,
      k: k,
      scale: 0.6 * :math.pow(k, 1.2),
      cut: 0.43 + 0.028 * k,
      drift: t * (0.15 + 0.06 * k),
      wide: 2.4 + k * 1.2,
      bright: (0.25 + 0.75 * sc.lit) * (1.05 - k * 0.05) * (0.4 + 0.6 * sc.glow),
      z: t * 0.22 + k * 3.1,
      z2: t * 2.2 + k,
      across: 1.3 / :math.sqrt(k),
      sx: sc.sx
    }

    {g, _} = Enum.reduce(0..(@cols - 1), {g, 0}, fn c, acc -> swell(acc, row, c) end)
    g
  end

  defp swell({g, run}, row, c) do
    x = c + 0.5
    # A crest, unless it has already run longer than a wave this far out.
    wave = noise((x + row.drift) / row.scale, row.r, row.z) > row.cut
    run = if wave, do: run + 1, else: 0

    {wave, run} =
      if run > 0 and
           run > (1.4 + 1.2 * row.k) * (0.7 + 0.6 * Hash.murmur(floor(x + row.drift), row.r, 9)),
         do: {false, 0},
         else: {wave, run}

    q = (x - row.sx) / row.wide
    path = :math.exp(-(q * q)) * row.bright
    glint = noise(x * row.across, row.r + 40, row.z2) * path

    ch =
      cond do
        glint > 0.45 -> "="
        glint > 0.3 or (wave and path > 0.3) -> "-"
        glint > 0.2 -> "·"
        wave and row.k > 3 -> "~"
        wave -> "-"
        true -> nil
      end

    {if(ch, do: Map.put(g, {row.r, c}, ch), else: g), run}
  end
end
