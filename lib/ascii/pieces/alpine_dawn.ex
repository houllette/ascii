defmodule Ascii.Pieces.AlpineDawn do
  @moduledoc """
  Snow peaks catching first light above a still, misty mountain lake.

  Jagged snow peaks catch the first pink light on their east faces while
  their flanks stay in blue shadow. Mist pools along the far shore and a
  still lake mirrors it all. The light warms toward gold as the sun clears
  the ridge, the mist drifts, and slow ripples cross the water.

  The range is a heightfield, raymarched once from a camera just above the
  water: each cell keeps its depth, height, sunlight (with cast shadows) and
  snow cover, so a frame only re-tints it. The lake looks up the picture
  above it along each cell's reflected ray. Every cell is then drawn as a
  halftone dot, ordered-dithered, in the palette colour nearest its hue.

  Ported from `src/pieces/alpine-dawn.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Palette, Scene}
  import Bitwise

  @meta %Ascii.Meta{
    name: "alpine dawn",
    category: :scenes,
    note: "snow peaks catching first light above a still, misty mountain lake",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#090c18",
    palette: [
      "#0e1430",
      "#151d40",
      "#1d2752",
      "#263365",
      "#314179",
      "#3e508c",
      "#4f62a0",
      "#6577b3",
      "#8090c4",
      "#9eaad3",
      "#bec6e2",
      "#4b3e6c",
      "#6a5482",
      "#8c6a92",
      "#b0829c",
      "#cf96a4",
      "#e8a9a8",
      "#f5bcaa",
      "#ffd0b0",
      "#ffe2c2",
      "#fff1e0",
      "#fdfaf6",
      "#ffc887",
      "#f7a965",
      "#f2a08f",
      "#e58a87",
      "#f8b59d",
      "#d97b7e",
      "#7a4c4a",
      "#a5654f",
      "#523a4a",
      "#1b2034",
      "#262c45",
      "#363c59",
      "#0a1418",
      "#0f1f24",
      "#162a2f",
      "#203a3c",
      "#a3a7c6",
      "#c6c3d8",
      "#e0d4dc",
      "#5a4f7e",
      "#7b6c9c",
      "#9a8cb6",
      "#b8a8c8",
      "#d8bccb"
    ]
  }

  @w 200
  @h 100
  # The tangent of half the field of view, across the width.
  @k 0.62
  # Eye level, in rows.
  @hz 56.5
  # The camera's height above the water.
  @cam 1.5
  # The distance to the far shore.
  @shore_z 46
  # The first row of open water; the rows above it are the range's.
  @shore 62
  @sun_x 151
  @sun_y 50
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()

  # Peaks as pyramids, each turned a little, placed by where their summits
  # should land on screen: {column, row, distance, spread, turn}.
  @peaks [
    {66, 11, 140, 0.95, 0.3},
    {38, 26, 115, 1.1, -0.15},
    {116, 22, 175, 0.9, 0.2},
    {92, 33, 150, 1.0, 0.1},
    {96, 25, 340, 1.1, 0.4},
    {180, 38, 200, 1.5, -0.1},
    {8, 30, 160, 1.2, 0.25}
  ]

  # The near pines: {column, tip row, size}.
  @pines [
    {9, 5, 1.15},
    {20, 38, 0.85},
    {32, 66, 0.5},
    {192, 10, 1.15},
    {181, 40, 0.75},
    {204, 26, 1}
  ]

  # The lake's rows.
  @lr @h - @shore
  # The mist: a wrapping sheet from row @m0 to just below the shore.
  @mw 480
  @m0 36
  @mr @shore + 2 - @m0
  # The high cloud.
  @cw 640
  @cr 34

  # The dots' gamma, and power/2's range and the margin its decisions keep;
  # see dot/7.
  @gamma 1.1
  @power_lo -20
  @margin 1.0e-8

  @mul_lo band(1_274_126_177, 0xFFFF)
  # The lake's floor, as its Float32Array holds 0.26.
  <<lake_floor::float-32>> = <<0.26::float-32>>
  @lake_floor lake_floor

  @impl true
  def meta, do: @meta

  # Called for nearly every cell of every frame: local, so they inline.
  @compile {:inline,
            clamp: 1,
            smooth: 3,
            mix: 3,
            f32: 1,
            hash: 2,
            scramble: 1,
            tint: 6,
            cube: 1,
            ripple: 3,
            round_js: 1,
            power: 2}
  defp clamp(v) when v < 0, do: 0.0
  defp clamp(v) when v > 1, do: 1.0
  defp clamp(v), do: v

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  # A store into a Float32Array.
  defp f32(x) do
    <<y::float-32>> = <<x::float-32>>
    y
  end

  # The scenes' hash (`Ascii.Kit.Hash.scene/2`) of two integers, inlined:
  # `Math.imul(x, A) + Math.imul(y, B)` agrees with `x * A + y * B` modulo
  # 2^32, which is all the rest reads.
  defp hash(x, y), do: scramble(x * 374_761_393 + y * 668_265_263)

  defp scramble(h) do
    h = band(h, 0xFFFFFFFF)
    h = bxor(h, bsr(h, 13))
    # Math.imul(h, 1274126177) in halves, so no product passes 2^60.
    h =
      band(
        band(h, 0xFFFF) * 1_274_126_177 + bsl(band(bsr(h, 16) * @mul_lo, 0xFFFF), 16),
        0xFFFFFFFF
      )

    bxor(h, bsr(h, 16)) / 4_294_967_296
  end

  # Value noise (`Ascii.Kit.Scene.noise/3` with no period), with the four
  # corner hashes sharing their products.
  defp noise(x, y) do
    xi = floor(x)
    yi = floor(y)
    fx = x - xi
    fy = y - yi
    u = fx * fx * (3 - 2 * fx)
    v = fy * fy * (3 - 2 * fy)
    xa = xi * 374_761_393
    yb = yi * 668_265_263
    a = scramble(xa + yb)
    b = scramble(xa + 374_761_393 + yb)
    c = scramble(xa + yb + 668_265_263)
    d = scramble(xa + 374_761_393 + yb + 668_265_263)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  defp fbm(x, y, octaves), do: fbm(x, y, octaves, 0, 0, 0.5, 1)

  defp fbm(_x, _y, 0, s, n, _amp, _f), do: s / n

  defp fbm(x, y, octaves, s, n, amp, f),
    do: fbm(x, y, octaves - 1, s + amp * noise(x * f, y * f), n + amp, amp * 0.5, f * 2)

  # Sharp crests where plain noise crosses its middle: rock ribs and couloirs.
  defp ridged(x, y, octaves), do: ridged(x, y, octaves, 0, 0, 0, 0.5, 1)

  defp ridged(_x, _y, octaves, octaves, s, n, _amp, _f), do: s / n

  defp ridged(x, y, octaves, i, s, n, amp, f) do
    v = 1 - abs(2 * noise(x * f + i * 17.3, y * f) - 1)
    ridged(x, y, octaves, i + 1, s + amp * v * v, n + amp, amp * 0.5, f * 2.1)
  end

  defp peaks do
    for {sx, row, z, f, a} <- @peaks do
      h = @cam + (@hz - row) / 100 * @k * z - 1.5
      {(sx - 100) / 100 * @k * z, z, h, h * f, :math.cos(a), :math.sin(a)}
    end
  end

  # The highest peak over a point, the hills beyond the shore, and the
  # crags. Hills are under 4 high, so they cannot top a peak of 4 or more,
  # and crags weigh nothing below 4: both are skipped where they add zero.
  defp terrain(x, z, peaks) do
    h = peak_height(peaks, x, z, 0)

    h =
      if z > @shore_z and h < 4 do
        hills = (1 + 3 * fbm(x * 0.04, z * 0.04, 3)) * smooth(@shore_z, @shore_z + 15, z)
        if hills > h, do: hills, else: h
      else
        h
      end

    # Crags, deeper on the high ground.
    if h > 4,
      do:
        h +
          ((ridged(x * 0.06, z * 0.06, 3) - 0.45) * 6 + (ridged(x * 0.2, z * 0.2, 2) - 0.45) * 1.6) *
            smooth(4, 22, h),
      else: h
  end

  defp peak_height([], _x, _z, h), do: h

  defp peak_height([{px, pz, ph, pr, c, s} | peaks], x, z, h) do
    dx = x - px
    dz = z - pz
    rx = dx * c - dz * s
    rz = dx * s + dz * c
    v = ph * (1 - (abs(rx) + abs(rz)) / pr)
    peak_height(peaks, x, z, if(v > h, do: v, else: h))
  end

  # Distance along a ray from height `oy` with slope `v` and spread `u` to
  # the terrain beyond the shore, or 0 when it reaches the sky.
  defp march(u, v, oy, peaks), do: march(u, v, oy, peaks, @shore_z, @shore_z, 0)

  defp march(u, v, oy, peaks, z, prev, i) when i < 260 and z < 520 do
    gap = oy + v * z - terrain(u * z, z, peaks)

    if gap < 0,
      do: bisect(u, v, oy, peaks, prev, z, 0),
      else: march(u, v, oy, peaks, z + (max(0.35, gap * 0.45) + z * 0.002), z, i + 1)
  end

  defp march(_u, _v, _oy, _peaks, _z, _prev, _i), do: 0

  defp bisect(_u, _v, _oy, _peaks, _a, b, 7), do: b

  defp bisect(u, v, oy, peaks, a, b, j) do
    m = (a + b) / 2

    if oy + v * m - terrain(u * m, m, peaks) < 0,
      do: bisect(u, v, oy, peaks, a, m, j + 1),
      else: bisect(u, v, oy, peaks, m, b, j + 1)
  end

  @impl true
  def init(_options) do
    peaks = peaks()
    n = JSMath.hypot(0.9, 0.3, 0.14)
    light = {0.9 / n, 0.3 / n, 0.14 / n}

    # --- the range, raymarched once ---------------------------------------
    range =
      for r <- 0..(@shore - 1) do
        v = (@hz - (r + 0.5)) / 100 * @k
        List.to_tuple(for x <- 0..(@w - 1), do: range_cell(x, v, peaks, light))
      end
      |> List.to_tuple()

    tree_top = tree_top()
    src = lake_sources(peaks, tree_top)
    fg = foreground()

    # A faint large-scale unevenness, so the open sky and the deep water are
    # never one flat halftone screen.
    hz =
      List.to_tuple(
        for r <- 0..(@h - 1) do
          List.to_tuple(for x <- 0..(@w - 1), do: f32(fbm(x * 0.03, r * 0.06, 3)))
        end
      )

    upper =
      for r <- 0..(@shore - 1) do
        range_row = elem(range, r)
        # Row 0 has no row above it, and no crest.
        above = if r > 0, do: elem(range, r - 1), else: List.to_tuple(List.duplicate(:none, @w))

        cells =
          for x <- 0..(@w - 1) do
            upper_static(x, r, elem(range_row, x), elem(above, x), hz, tree_top, fg)
          end

        {r, r + 0.5, cells}
      end

    lower =
      for r <- @shore..(@h - 1) do
        y = r + 0.5
        d = (y - @shore) / @lr
        src_row = elem(src, r - @shore)
        cells = for x <- 0..(@w - 1), do: lower_static(x, r, elem(src_row, x), hz, fg)
        {r, y, {d, 0.4 + 1.4 * d, 0.68 - 0.32 * d, 0.4 + 0.5 * d}, cells}
      end

    %{
      upper: upper,
      lower: lower,
      mist: mist_sheet(),
      cloud: cloud_sheet(),
      power: power_table(),
      lut: Palette.nearest_lut(@meta.palette),
      # Set only by the tests: every shortcut a frame takes (the dot's fast
      # power and its margins, the lake's shared lattice) is then taken the
      # long way, so the two can be checked against each other.
      exact?: false
    }
  end

  defp range_cell(x, v, peaks, {l0, l1, l2} = light) do
    u = (x + 0.5 - 100) / 100 * @k

    case march(u, v, @cam, peaks) do
      0 ->
        nil

      z ->
        px = u * z
        py = @cam + v * z
        e = 0.35
        hx = (terrain(px + e, z, peaks) - terrain(px - e, z, peaks)) / (2 * e)
        hz = (terrain(px, z + e, peaks) - terrain(px, z - e, peaks)) / (2 * e)
        nl = JSMath.hypot(hx, 1, hz)
        nx = -hx / nl
        ny = 1 / nl
        nz = -hz / nl
        lit = max(0, nx * l0 + ny * l1 + nz * l2)
        lit = if lit > 0 and shadowed?(px, py, z, light, peaks, 0.8), do: 0, else: lit
        grain = fbm(px * 0.4, py * 0.25, 2)
        # Rock shows through in couloirs running down the fall line.
        gully = ridged(px * 0.22 + z * 0.05, py * 0.045, 2)

        snow =
          smooth(0.36, 0.52, ny + 0.3 * (grain - 0.5)) * smooth(5, 11, py + 5 * grain) *
            (1 - 0.75 * smooth(0.62, 0.85, gully))

        {f32(z), f32(py), f32(lit), f32(ny), f32(snow)}
    end
  end

  # Cast shadow: walk toward the sun.
  defp shadowed?(px, py, z, {l0, l1, l2} = light, peaks, s) when s < 160 do
    qz = z + l2 * s

    cond do
      qz < @shore_z -> false
      py + l1 * s + 0.15 < terrain(px + l0 * s, qz, peaks) -> true
      true -> shadowed?(px, py, z, light, peaks, s + (0.6 + s * 0.04))
    end
  end

  defp shadowed?(_px, _py, _z, _light, _peaks, _s), do: false

  # --- the far shore's treeline ---------------------------------------------
  defp tree_top do
    tops =
      List.to_tuple(for x <- 0..(@w - 1), do: f32(@shore - 0.6 - 1.2 * fbm(x * 0.06, 2.3, 2)))

    Stream.unfold(-2, fn tx ->
      if tx < @w + 2, do: {tx, tx + (1.6 + hash(trunc(tx * 9), 7) * 2.2)}
    end)
    |> Enum.reduce(tops, fn tx, tops ->
      tip = @shore - 2.6 - hash(trunc(tx * 3), 8) * 4 - 1.5 * smooth(60, 0, tx)
      slope = 1.1 + hash(trunc(tx * 5), 9) * 0.5

      for x <- max(0, floor(tx - 6))..(@w - 1)//1, x < tx + 6, reduce: tops do
        tops -> put_elem(tops, x, f32(min(elem(tops, x), tip + abs(x + 0.5 - tx) * slope)))
      end
    end)
  end

  # --- the lake: where each cell's reflected ray lands in the picture above -
  defp lake_sources(peaks, tree_top) do
    List.to_tuple(
      for r <- @shore..(@h - 1) do
        v = (@hz - (r + 0.5)) / 100 * @k

        List.to_tuple(
          for x <- 0..(@w - 1) do
            u = (x + 0.5 - 100) / 100 * @k
            z = march(u, -v, -@cam, peaks)
            vs = -v - if(z != 0, do: 2 * @cam / z, else: 0)
            row = @hz - vs * 100 / @k - 0.5
            # The treeline stands on the shore.
            mirror = 2 * @shore - 1 - r
            f32(if mirror >= elem(tree_top, x), do: mirror, else: row)
          end
        )
      end
    )
  end

  # --- the near pines and the bank they stand on ----------------------------
  defp foreground do
    banks =
      for x <- 0..(@w - 1) do
        {88 + 14 * smooth(0, 52, x) + 2 * fbm(x * 0.2, 1, 2),
         90 + 12 * smooth(@w, @w - 40, x) + 2 * fbm(x * 0.2, 4, 2)}
      end

    List.to_tuple(
      for r <- 0..(@h - 1) do
        y = r + 0.5

        List.to_tuple(
          for {{bank_l, bank_r}, x} <- Enum.with_index(banks) do
            fg = if y > bank_l or y > bank_r, do: {f32(0.15 * hash(x, r)), 0}
            fg = Enum.reduce(@pines, fg, &pine(&1, &2, x, r, y))
            fg && foreground_color(fg)
          end
        )
      end
    )
  end

  defp pine({_px, tip, _s}, fg, _x, _r, y) when y - tip < 0, do: fg

  defp pine({px, tip, s}, fg, x, r, y) do
    d = y - tip
    tier = 3.4 * s
    f = d / tier - floor(d / tier)

    hw =
      (0.4 + d * 0.2) * (0.5 + 0.5 * f) *
        (1 + 0.6 * (hash(r, floor(px) * 7) - 0.5) * smooth(0, 8, d))

    dx = x + 0.5 - px

    cond do
      abs(dx) > hw ->
        fg

      # The outline catches the dawn sky: a warm rim on the side facing the
      # sun, a dim cool one on the other, the inside stays black. The rim is
      # light from the sky behind, so it fades out below the shore.
      hw - abs(dx) < 1 ->
        sunward = if px < @sun_x, do: dx > 0, else: dx < 0

        {if(sunward, do: 1, else: 0.5), f32(smooth(70, 44, y) * (0.75 + 0.25 * hash(x, r * 7)))}

      true ->
        {f32(0.3 * hash(x * 3, r * 5)), 0}
    end
  end

  # Black against it all, rimmed on the sun side.
  defp foreground_color({s, e}) do
    cr = f32(0.02 + 0.05 * s)
    cg = f32(0.04 + 0.06 * s)
    cb = f32(0.05 + 0.06 * s)

    cond do
      # Warm on the side facing the sun.
      e > 0 and s == 1 ->
        {f32(mix(cr, 0.62, e)), f32(mix(cg, 0.4, e)), f32(mix(cb, 0.38, e)), f32(0.12 * e)}

      # Cool lilac from the sky on the other.
      e > 0 and s == 0.5 ->
        {f32(mix(cr, 0.2, e)), f32(mix(cg, 0.22, e)), f32(mix(cb, 0.36, e)), f32(0.22 * e)}

      true ->
        {cr, cg, cb, 0}
    end
  end

  # --- mist, a wrapping sheet that drifts along the valley ------------------
  defp mist_sheet do
    List.to_tuple(
      for r <- 0..(@mr - 1) do
        y = r + @m0

        List.to_tuple(
          for x <- 0..(@mw - 1) do
            q = Scene.fbm(x * 0.0125, y * 0.1, 2, @mw * 0.0125)
            f32(Scene.fbm(x * 0.025 + q * 1.4, y * 0.22 + q, 4, @mw * 0.025))
          end
        )
      end
    )
  end

  # --- thin high cloud, streaked and lit from below by the sun --------------
  defp cloud_sheet do
    List.to_tuple(
      for r <- 0..(@cr - 1) do
        y = r + 0.5

        List.to_tuple(
          for x <- 0..(@cw - 1) do
            q = Scene.fbm(x * 0.0125, y * 0.12, 2, 8)
            c = Scene.fbm(x * 0.025 + q * 2, y * 0.2 + q * 0.8, 4, 16)

            f32(
              smooth(0.52, 0.7, c - 0.06 * abs(y - 18) / 10) * smooth(5, 13, y) *
                smooth(33, 24, y)
            )
          end
        )
      end
    )
  end

  # Everything about a cell above the water that does not move.
  defp upper_static(x, r, range, above, hz, tree_top, fg) do
    y = r + 0.5
    bayer = elem(@bayer, band(r, 3) * 4 + band(x, 3))
    # The sky's colour at a point, for the sky itself and as haze on the peaks.
    v = clamp(y / 52)
    east = smooth(20, 190, x)
    dx = x + 0.5 - @sun_x
    dy = (y - @sun_y) * 2.2
    ds = :math.sqrt(dx * dx + dy * dy)
    low = :math.pow(v, 1.9)
    # Indigo overhead, a soft unevenness in it, then a pale lilac and rose
    # band behind the range, lighter than the mountains' shadowed flanks.
    veil = (elem(elem(hz, r), x) - 0.5) * 0.1 * (1 - v)
    sky_r = f32(0.03 + veil + low * (0.56 + 0.2 * east))
    sky_g = f32(0.04 + veil + low * (0.48 + 0.02 * east))
    sky_b = f32(0.13 + veil * 1.6 + low * (0.62 - 0.12 * east))
    # The sun's glow, kept apart so it can breathe.
    glow =
      f32(:math.exp(-ds / 6) * 0.65 + :math.exp(-ds / 15) * 0.2 + :math.exp(-ds / 50) * 0.1)

    body =
      case range do
        nil -> sky_static(x, r, y)
        _ -> peak_static(range, above)
      end

    top = elem(tree_top, x)

    tree =
      if y >= top do
        # The far shore's pines, dark against the mist.
        s = 0.4 + 0.6 * hash(x * 7, r * 3)
        {0.04 + 0.03 * s, 0.06 + 0.04 * s, 0.1 + 0.05 * s, smooth(top + 1, @shore, y)}
      end

    fixed =
      case elem(elem(fg, r), x) do
        nil -> nil
        {cr, cg, cb, fl} -> fixed(cr, cg, cb, fl, 1, bayer)
      end

    {x, bayer, sky_r, sky_g, sky_b, glow, body, tree, fixed}
  end

  defp peak_static({z, alt, sun, up, snow}, above) do
    amb = (0.55 + 0.45 * up) * (0.55 + 0.5 * smooth(4, 34, alt))
    # Forested foothills.
    wood = smooth(9, 4, alt) * smooth(110, 75, z)
    # Distance hazes toward the sky behind, and haze settles in the far
    # valleys so each ridge stands clear of the one behind it.
    fog = smooth(16, 3, alt) * smooth(70, 150, z) * 0.6
    haze = max(fog, clamp(1 - :math.exp(-(z - @shore_z) / 260)) * 0.45)
    # Sunlit terrain with open sky directly above: the crest line.
    rim = above == nil and sun > 0

    {:peak, snow, sun, alt, {0.13 * amb, 0.17 * amb, 0.36 * amb}, 0.5 * smooth(14, 36, alt), wood,
     haze, mix(0.42, 0.3, wood), rim}
  end

  defp sky_static(x, r, y) do
    # A few stars still out in the west.
    star =
      if y < 34 and hash(x, r * 3 + 11) > 0.985,
        do: {1.5 + hash(x, r) * 3, hash(r, x) * 6.28, smooth(150, 40, x), smooth(34, 6, y)}

    # High cloud, rose-gold toward the sun and mauve away from it.
    cloud =
      if r < @cr do
        g = :math.exp(-JSMath.hypot(x + 0.5 - @sun_x, (y - @sun_y) * 1.6) / 55)
        b = clamp(0.25 + 0.9 * g)
        {0.35 + 0.65 * smooth(40, 150, x), mix(0.32, 1, b), b, mix(0.4, 0.5, b)}
      end

    # The sun, just clearing the ridge.
    dx = x + 0.5 - @sun_x
    dy = y - @sun_y
    ds = :math.sqrt(dx * dx + dy * dy)
    disc = if ds < 4.5, do: smooth(4.5, 3.3, ds)

    {:sky, star, cloud, disc}
  end

  defp lower_static(x, r, src, hz, fg) do
    y = r + 0.5
    d = (y - @shore) / @lr
    bayer = elem(@bayer, band(r, 3) * 4 + band(x, 3))
    # The bottom rows thin out into the ground.
    fade = f32(smooth(@h + 2, @h - 22, y))

    case elem(elem(fg, r), x) do
      # The near pines and the bank, black against it all.
      {cr, cg, cb, fl} ->
        fixed(cr, cg, cb, fl, 1, bayer)

      # A dark seam where the shore meets the water.
      nil when r == @shore ->
        fixed(f32(0.06), f32(0.12), f32(0.14), 0, fade, bayer)

      nil ->
        # Slow unevenness in the dark water.
        deep = (elem(elem(hz, r), x) - 0.5) * 0.1 * d
        # The sun's road.
        road_w = 1.5 + (y - @shore) * 0.45
        road = :math.exp(-:math.pow((x + 0.5 - @sun_x) / road_w, 2))

        {x, bayer, src, 0.02 + deep, 0.035 + deep, 0.07 + deep * 1.6, road, fade}
    end
  end

  # A cell that never changes: its dot and the colour it looks up.
  defp fixed(cr, cg, cb, fl, fade, bayer) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(fl + (1 - fl) * :math.pow(peak, @gamma)) * fade
    step = max(0, min(3, JSMath.round(level * 3 + bayer)))
    {r, g, b} = tint(cr, cg, cb, level, step, peak)
    # The colour's key in the cache, as Palette.nearest/4 makes it.
    key =
      bsl(min(31, trunc(r * 31.99)), 10) ||| bsl(min(31, trunc(g * 31.99)), 5) |||
        min(31, trunc(b * 31.99))

    {:fixed, elem(@dots, step), key, r, g, b}
  end

  @impl true
  def frame(state, t, env) do
    # Rose first light warming toward gold.
    warm = 0.75 - 0.5 * :math.exp(-t / 60)
    # The sunlit line creeps down the slopes.
    line = 6 + 4 * :math.exp(-t / 70)
    drift = t * 1.1
    # The sun's glow breathes.
    pulse = 1 + 0.06 * :math.sin(t / 8 * :math.pi() * 2)
    # The warm light, from rose toward gold.
    lg = mix(0.6, 0.8, warm)
    lb = mix(0.55, 0.4, warm)

    light =
      {pulse, line, line + 7, {lg - 0.12, lg + 0.14}, {lb + 0.02, lb + 0.12},
       {mix(0.89, 0.95, warm), mix(0.76, 0.88, warm)}, mix(0.62, 0.74, warm), t}

    cols = columns(t, warm, drift)
    acc = {<<>>, <<>>, state.lut, env.color?, if(state.exact?, do: :exact, else: state.power)}

    {a_rows, acc} =
      Enum.reduce(state.upper, {[], acc}, fn {r, y, cells}, {a_rows, acc} ->
        mist_row = if r >= @m0, do: elem(state.mist, r - @m0)
        cloud_row = if r < @cr, do: elem(state.cloud, r)
        rows = {mist_row, cloud_row, y}
        {a, acc} = upper_cells(cells, rows, cols, light, [], acc)
        {[List.to_tuple(:lists.reverse(a)) | a_rows], newline(acc)}
      end)

    a_rows = a_rows |> :lists.reverse() |> List.to_tuple()

    {cols, bases} = ripple_columns(t * 0.06, t * 0.1, t * 0.04, state.exact?)
    lake = {cols, 0.5 + 0.5 * warm, a_rows}

    {text, colors, lut, color?, _} =
      Enum.reduce(state.lower, acc, fn {r, y, row, cells}, acc ->
        ripples = ripple_row(bases, y * 0.5 - t * 0.35, y * 1.1 - t * 0.7, y * 1.9 - t * 0.45)
        acc = lake_cells(cells, ripples, row, lake, acc)
        if r < @h - 1, do: newline(acc), else: acc
      end)

    {text, if(color?, do: colors), %{state | lut: lut}}
  end

  defp newline({text, colors, lut, color?, power}),
    do: {<<text::binary, ?\n>>, colors, lut, color?, power}

  defp columns(t, warm, drift) do
    List.to_tuple(
      for x <- 0..(@w - 1) do
        wisp = f32(noise((x + drift * 0.6) * 0.06, 3.7))
        # Mist pooled in the valley behind the shore, lit rose toward the sun.
        e = smooth(20, 170, x) * (0.6 + 0.4 * warm)
        near = :math.exp(-abs(x + 0.5 - @sun_x) / 22) * 0.3
        sx = x + t * 0.8
        ix = floor(sx)

        {wisp, mix(0.48, 0.9, e) + near, mix(0.46, 0.7, e) + near * 0.75,
         mix(0.7, 0.7, e) + near * 0.5, rem(floor(x + drift), @mw),
         rem(floor(x * 0.7 + drift * 1.9 + 211), @mw), rem(ix, @cw), rem(ix + 1, @cw), sx - ix}
      end
    )
  end

  defp upper_cells([], _rows, _cols, _light, a, acc), do: {a, acc}

  defp upper_cells([cell | cells], rows, cols, light, a, acc) do
    {cr, cg, cb, fl} = c = upper_cell(cell, elem(cols, elem(cell, 0)), rows, light)

    acc =
      case elem(cell, 8) do
        nil -> dot(cr, cg, cb, fl, 1, elem(cell, 1), acc)
        fixed -> fixed_dot(fixed, acc)
      end

    upper_cells(cells, rows, cols, light, [c | a], acc)
  end

  # The far shore's pines, dark against the mist, and low wisps drifting
  # across their feet.
  defp upper_cell({_, _, _, _, _, _, _, {tr, tg, tb, k}, _}, col, {mist_row, _, _}, _light) do
    {_, mr, mg, mb, _, ti, _, _, _} = col
    a = smooth(0.45, 0.72, elem(mist_row, ti)) * k * 0.6
    {f32(mix(tr, mr, a)), f32(mix(tg, mg, a)), f32(mix(tb, mb, a)), 0.0}
  end

  defp upper_cell({_, _, sky_r, sky_g, sky_b, glow, body, nil, _}, col, rows, light) do
    gl = glow * elem(light, 0)
    # Gold at the core, rose further out.
    gg = 0.62 + 0.28 * smooth(0.15, 0.7, gl)
    cr = sky_r + gl
    cg = sky_g + gl * gg
    cb = sky_b + gl * (gg - 0.22)
    {cr, cg, cb, fl} = body(body, cr, cg, cb, col, rows, light)
    mist(rows, col, cr, cg, cb, fl)
  end

  defp body(
         {:peak, sn, sun, alt, {a13, a17, a36}, gold_hi, wood, haze, fl0, rim},
         cr0,
         cg0,
         cb0,
         _col,
         _rows,
         light
       ) do
    {_, line, line7, {g_lo, g_hi}, {b_lo, b_hi}, rim_c, _, _} = light
    lit = sun * smooth(line, line7, alt)
    # Snow: deep blue in shadow, rose to gold in the sun, ending sharply.
    sl = smooth(0.08, 0.24, lit)
    # Full on faces and summits glow gold, glancing light stays rose.
    gold = clamp(0.6 * smooth(0.25, 0.8, lit) + gold_hi)
    br = 0.78 + 0.3 * lit
    sr = mix(a13, br, sl)
    sg = mix(a17, mix(g_lo, g_hi, gold) * br, sl)
    sb = mix(a36, mix(b_lo, b_hi, gold) * br, sl)
    # Rock: slate in shadow, warm umber in the sun.
    cr = mix(mix(0.06, 0.4, sl), sr, sn)
    cg = mix(mix(0.07, 0.2, sl), sg, sn)
    cb = mix(mix(0.14, 0.2, sl), sb, sn)
    cr = mix(mix(cr, 0.07, wood), cr0, haze)
    cg = mix(mix(cg, 0.09, wood), cg0, haze)
    cb = mix(mix(cb, 0.18, wood), cb0, haze)
    # The shadowed range still carries a dim blue screen; the wooded
    # foothills in front of it drop away to near black.
    fl = mix(fl0, 0.04, sl)

    # The first light catches the crest itself in a bright line.
    if rim and sl > 0.3 do
      {rim_g, rim_b} = rim_c
      {mix(cr, 1, sl), mix(cg, rim_g, sl), mix(cb, rim_b, sl), fl}
    else
      {cr, cg, cb, fl}
    end
  end

  defp body({:sky, star, cloud, disc}, cr, cg, cb, col, {_, cloud_row, _}, light) do
    {cr, cg, cb} = star(star, cr, cg, cb, elem(light, 7))
    {cr, cg, cb} = cloud(cloud, cr, cg, cb, col, cloud_row, light)

    case disc do
      nil -> {cr, cg, cb, 0.21}
      a -> {mix(cr, 1, a), mix(cg, 0.96, a), mix(cb, 0.86, a), 0.21}
    end
  end

  defp star(nil, cr, cg, cb, _t), do: {cr, cg, cb}

  defp star({speed, phase, west, high}, cr, cg, cb, t) do
    tw = 0.6 + 0.4 * :math.sin(t * speed + phase)
    s = tw * west * high * 0.75
    {max(cr, s * 0.9), max(cg, s * 0.92), max(cb, s)}
  end

  defp cloud(nil, cr, cg, cb, _col, _row, _light), do: {cr, cg, cb}

  defp cloud({k, kr, b, kb}, cr, cg, cb, col, row, light) do
    {_, _, _, _, _, _, i0, i1, fx} = col
    c0 = elem(row, i0)
    c = (c0 + (elem(row, i1) - c0) * fx) * k

    if c > 0.01 do
      kg = mix(0.24, elem(light, 6), b)
      {mix(cr, kr, c * 0.75), mix(cg, kg, c * 0.75), mix(cb, kb, c * 0.75)}
    else
      {cr, cg, cb}
    end
  end

  defp mist({nil, _, _}, _col, cr, cg, cb, fl), do: {f32(cr), f32(cg), f32(cb), f32(fl)}

  defp mist({mist_row, _, y}, col, cr, cg, cb, fl) do
    {wisp, mr, mg, mb, mi, _, _, _, _} = col
    m = elem(mist_row, mi)
    # A ragged top edge: the sheet heaves in long swells and small tufts.
    edge = 5 * (m - 0.5) + 4 * (wisp - 0.5)
    band = smooth(@m0 + 14, @shore - 3, y + edge)
    a = (0.3 + 0.7 * smooth(0.32, 0.64, m)) * band * 0.6
    fl = if a > 0.05, do: max(fl, 0.2), else: fl
    {f32(mix(cr, mr, a)), f32(mix(cg, mg, a)), f32(mix(cb, mb, a)), f32(fl)}
  end

  # The lake's three ripples are value noise at x * 0.045 + t * 0.06,
  # x * 0.12 - t * 0.1 and x * 0.03 + t * 0.04 across, so a frame works out
  # each column's lattice cell and blend once, and each row hashes only the
  # lattice points its cells fall between: the same sums as noise/2, from
  # far fewer hashes.
  defp ripple_columns(ta, tc, te, true) do
    cols = for x <- 0..(@w - 1), do: {x * 0.045 + ta, nil, x * 0.12 - tc, nil, x * 0.03 + te, nil}
    {List.to_tuple(cols), :exact}
  end

  defp ripple_columns(ta, tc, te, false) do
    cols =
      for x <- 0..(@w - 1),
          do: {lattice(x * 0.045 + ta), lattice(x * 0.12 - tc), lattice(x * 0.03 + te)}

    [{{b1, _}, {b2, _}, {b3, _}} | _] = cols
    {{e1, _}, {e2, _}, {e3, _}} = List.last(cols)

    cols =
      for {{i1, u1}, {i2, u2}, {i3, u3}} <- cols, do: {i1 - b1, u1, i2 - b2, u2, i3 - b3, u3}

    {List.to_tuple(cols), {{b1, e1 - b1}, {b2, e2 - b2}, {b3, e3 - b3}}}
  end

  defp lattice(x) do
    xi = floor(x)
    fx = x - xi
    {xi, fx * fx * (3 - 2 * fx)}
  end

  defp ripple_row(:exact, y1, y2, y3), do: {{:at, y1}, {:at, y2}, {:at, y3}}

  defp ripple_row({{b1, n1}, {b2, n2}, {b3, n3}}, y1, y2, y3) do
    {lattice_row(b1, n1, y1), lattice_row(b2, n2, y2), lattice_row(b3, n3, y3)}
  end

  defp lattice_row(base, n, y) do
    {yi, v} = lattice(y)
    lo = List.to_tuple(for i <- 0..(n + 1), do: hash(base + i, yi))
    hi = List.to_tuple(for i <- 0..(n + 1), do: hash(base + i, yi + 1))
    {lo, hi, v}
  end

  # noise/2 from its lattice: the corners' hashes and the blends. (Or
  # noise/2 itself, the long way.)
  defp ripple({:at, y}, x, nil), do: noise(x, y)

  defp ripple({lo, hi, v}, i, u) do
    a = elem(lo, i)
    b = elem(lo, i + 1)
    c = elem(hi, i)
    d = elem(hi, i + 1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  # The lake: the picture above, shaken a little by slow ripples.
  defp lake_cells([], _ripples, _row, _lake, acc), do: acc

  defp lake_cells([{:fixed, _, _, _, _, _} = fixed | cells], ripples, row, lake, acc),
    do: lake_cells(cells, ripples, row, lake, fixed_dot(fixed, acc))

  defp lake_cells([cell | cells], {r1, r2, r3} = ripples, row, lake, acc) do
    {x, bayer, src, dr, dg, db, road, fade} = cell
    {d, sway_k, refl, lift_k} = row
    {cols, glint_k, a_rows} = lake
    {i1, u1, i2, u2, i3, u3} = elem(cols, x)
    w1 = ripple(r1, i1, u1)
    w2 = ripple(r2, i2, u2)
    sway = (w1 - 0.5) * sway_k + (w2 - 0.5) * 0.5
    sx = max(0, min(@w - 1, round_js(x + sway)))
    sr = max(0, min(@shore - 1, round_js(src + (w2 - 0.5) * 0.6 * d)))
    w3 = ripple(r3, i3, u3)
    # Long, faint ripple lines.
    lift = 1 + (w3 - 0.5) * lift_k
    # The water gives back a little less colour than it was sent.
    {ar, ag, ab, _} = elem(elem(a_rows, sr), sx)
    grey = (ar + ag + ab) / 3
    glint = smooth(0.55, 0.85, w2) * road * glint_k
    cr = f32(dr + mix(grey, ar, 0.75) * refl * lift + glint)
    cg = f32(dg + mix(grey, ag, 0.75) * refl * lift + glint * 0.8)
    cb = f32(db + mix(grey, ab, 0.75) * refl * lift + glint * 0.6)
    lake_cells(cells, ripples, row, lake, dot(cr, cg, cb, @lake_floor, fade, bayer, acc))
  end

  # Math.round: halves toward +infinity.
  defp round_js(x) do
    c = ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end

  defp fixed_dot({:fixed, char, key, r, g, b}, {text, colors, {_, answers} = lut, true, power}) do
    {index, lut} =
      case answers do
        %{^key => index} -> {index, lut}
        _ -> Palette.nearest(lut, r, g, b)
      end

    {<<text::binary, char::binary>>, <<colors::binary, index>>, lut, true, power}
  end

  defp fixed_dot({:fixed, char, _key, _r, _g, _b}, {text, colors, lut, false, power}),
    do: {<<text::binary, char::binary>>, colors, lut, false, power}

  # Dot size from brightness, dithered. Then the colour makes up what the dot
  # size could not: a small dot is drawn brighter and a large one dimmer, so
  # a gradient stays smooth across the dither's steps.
  #
  # Math.pow is slow, so the level is first found with power/2, within
  # 1e-13 of pow(peak, 1.1). Every decision the level feeds (the dot's
  # rounding, the colour's step in the cache, a cache miss) is then checked:
  # when one sits within 1e-8 of its threshold, or the colour is not cached
  # yet, the cell is worked out again with :math.pow, so the result is
  # always upstream's.
  defp dot(cr, cg, cb, fl, fade, bayer, {_, _, _, _, :exact} = acc),
    do: exact_dot(cr, cg, cb, fl, fade, bayer, cr |> max(cg) |> max(cb) |> max(1.0e-4), acc)

  defp dot(cr, cg, cb, fl, fade, bayer, {text, colors, lut, color?, power} = acc) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(fl + (1 - fl) * power(peak, power)) * fade
    v = level * 3 + bayer
    whole = floor(v)
    f = v - whole

    if abs(f - 0.5) < @margin do
      exact_dot(cr, cg, cb, fl, fade, bayer, peak, acc)
    else
      # Math.round, away from the half.
      step = if f < 0.5, do: whole, else: whole + 1
      step = max(0, min(3, step))
      text = <<text::binary, elem(@dots, step)::binary>>

      case color? && cached(lut, tint(cr, cg, cb, level, step, peak)) do
        false -> {text, colors, lut, false, power}
        nil -> exact_color(cr, cg, cb, fl, fade, bayer, peak, {text, colors, lut, true, power})
        index -> {text, <<colors::binary, index>>, lut, true, power}
      end
    end
  end

  # x^1.1 for 1e-4 <= x < 2^12: x is m * 2^e with m in [1, 2), so it is
  # c^1.1 * (1 + d)^1.1 * 2^(1.1 e), where c is the middle of m's 128th of
  # [1, 2) and |d| <= 1/256. The first and last come from tables, the middle
  # from its binomial series to the d^4 term, which leaves under 2e-14 out.
  defp power_table do
    mant =
      List.to_tuple(
        for i <- 0..127 do
          c = 1 + (i + 0.5) / 128
          # 2^-52 / c turns m - c, counted in units of 2^-52, into d.
          {2.220446049250313e-16 / c, :math.pow(c, @gamma)}
        end
      )

    exps = List.to_tuple(for e <- @power_lo..11, do: :math.pow(2.0, @gamma * e))
    k2 = @gamma * (@gamma - 1) / 2
    k3 = k2 * (@gamma - 2) / 3
    {mant, exps, @gamma, k2, k3, k3 * (@gamma - 3) / 4}
  end

  defp power(x, {mant, exps, k1, k2, k3, k4}) do
    <<_::1, be::11, hi::7, rest::45>> = <<x::float>>
    i = be - 1023 - @power_lo

    if i >= 0 and i < tuple_size(exps) do
      {scale, base} = elem(mant, hi)
      d = (rest - 0x100000000000) * scale
      base * (1 + d * (k1 + d * (k2 + d * (k3 + d * k4)))) * elem(exps, i)
    else
      :math.pow(x, @gamma)
    end
  end

  # Dim cells keep some of their darkness in the colour too, so the shadows
  # sit back in deep blues rather than as a bright fine screen.
  defp tint(cr, cg, cb, level, step, peak) do
    want = if step != 0, do: min(1, (level + 0.06) / elem(@cover, step)), else: 0
    s = (0.3 + 0.7 * want) * mix(0.5, 1, smooth(0.08, 0.5, peak)) / peak
    {clamp(cr * s), clamp(cg * s), clamp(cb * s)}
  end

  # The cached palette index for a colour, as `Palette.nearest/4` keys it, or
  # nil when it is not cached yet or a channel sits within the margin of a
  # step of the cache.
  defp cached({_palette, answers}, {r, g, b}) do
    with kr when kr != nil <- cube(r),
         kg when kg != nil <- cube(g),
         kb when kb != nil <- cube(b) do
      key = bsl(kr, 10) ||| bsl(kg, 5) ||| kb

      case answers do
        %{^key => index} -> index
        _ -> nil
      end
    end
  end

  defp cube(c) do
    w = c * 31.99
    k = trunc(w)
    f = w - k
    if (f < @margin and k >= 1) or f > 1 - @margin, do: nil, else: min(31, k)
  end

  defp exact_level(fl, fade, peak), do: clamp(fl + (1 - fl) * :math.pow(peak, @gamma)) * fade

  defp exact_dot(cr, cg, cb, fl, fade, bayer, peak, {text, colors, lut, color?, power}) do
    level = exact_level(fl, fade, peak)
    step = max(0, min(3, JSMath.round(level * 3 + bayer)))
    text = <<text::binary, elem(@dots, step)::binary>>

    if color? do
      {r, g, b} = tint(cr, cg, cb, level, step, peak)
      {index, lut} = Palette.nearest(lut, r, g, b)
      {text, <<colors::binary, index>>, lut, true, power}
    else
      {text, colors, lut, false, power}
    end
  end

  # The colour alone, worked out exactly; the dot is already drawn.
  defp exact_color(cr, cg, cb, fl, fade, bayer, peak, {text, colors, lut, true, power}) do
    level = exact_level(fl, fade, peak)
    step = max(0, min(3, JSMath.round(level * 3 + bayer)))
    {r, g, b} = tint(cr, cg, cb, level, step, peak)
    {index, lut} = Palette.nearest(lut, r, g, b)
    {text, <<colors::binary, index>>, lut, true, power}
  end
end
