defmodule Ascii.Pieces.DesertNight do
  @moduledoc """
  The milky way over a lone acacia on moonless dunes, meteors falling.

  A moonless desert under the milky way. The galaxy's bright core sits low
  over a lone acacia on a dune crest and arches up across the sky, split by
  its dark dust lane; a distant town warms the far horizon and catches the
  dunes' faces. Stars twinkle, sand glints along the ridges, and now and
  then a meteor crosses.

  The dunes are a heightfield raymarched once, keeping each cell's depth,
  light and shadow. The sky is drawn with a random dither so its faint glow
  reads as star dust, softened toward an ordered one inside the band; the
  sand keeps an ordered dither so its slopes read as smooth surfaces. Each
  cell is one dot, in the palette colour nearest its hue.

  Ported from `src/pieces/desert-night.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Palette
  import Bitwise

  @meta %Ascii.Meta{
    name: "desert night",
    category: :scenes,
    note: "the milky way over a lone acacia on moonless dunes, meteors falling",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#04060c",
    palette: [
      "#0a1024",
      "#101830",
      "#16213f",
      "#1e2b50",
      "#283864",
      "#34477a",
      "#45598f",
      "#5a6fa6",
      "#7488bd",
      "#93a5d2",
      "#b6c3e4",
      "#d8e0f2",
      "#f4f6fb",
      "#fff3dc",
      "#ffe2b4",
      "#f5c98e",
      "#e2a86e",
      "#c4864f",
      "#9c6440",
      "#74492f",
      "#2a2230",
      "#3d2f3a",
      "#56404a",
      "#735358",
      "#946a62",
      "#b6836c",
      "#4a3b48",
      "#6b5562",
      "#8a6f7a",
      "#a88590",
      "#c9a3a3",
      "#e2bfb4",
      "#2a2448",
      "#3d3466",
      "#57498a",
      "#7a68a8",
      "#ffd8a8",
      "#cfe0ff",
      "#a9c4ff",
      "#ff9a52",
      "#e07a3e",
      "#0d0f1a",
      "#151827"
    ]
  }

  @w 200
  @h 100
  @k 0.62
  # Eye level, in rows.
  @hz 64
  @cam 6
  # No dune is taller.
  @hmax 16
  # The far glow, just under the horizon.
  @town_x 30
  @town_y 66
  # The galaxy's bright centre.
  @core_x 152
  @core_y 38
  # The milky way's arch: centre and radius; its angle at the core, and the
  # sweep to the west edge.
  @arc_x 50
  @arc_y 209.8
  @arc_r 199.8
  @arc_a -1.035
  @arc_s 0.8
  @acacia 150
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()

  # The first row the airglow drifts in: Math.floor(HZ * 0.3).
  @air0 19

  # The dots' gamma in the sky and on the ground.
  @gamma_sky 0.92
  @gamma_ground 0.75
  @power_lo -20
  @margin 1.0e-8
  @mul_lo band(1_274_126_177, 0xFFFF)
  # Values as their Float32Arrays hold them.
  <<f002::float-32>> = <<0.02::float-32>>
  <<f01::float-32>> = <<0.1::float-32>>
  <<f012::float-32>> = <<0.12::float-32>>
  <<f028::float-32>> = <<0.28::float-32>>
  @f002 f002
  @f01 f01
  @f012 f012
  @f028 f028

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

  # This scene's fBm shifts each octave along x by 31.7.
  defp fbm(x, y, octaves), do: fbm(x, y, octaves, 0, 0, 0, 0.5, 1)

  defp fbm(_x, _y, octaves, octaves, s, n, _amp, _f), do: s / n

  defp fbm(x, y, octaves, i, s, n, amp, f),
    do:
      fbm(
        x,
        y,
        octaves,
        i + 1,
        s + amp * noise(x * f + i * 31.7, y * f),
        n + amp,
        amp * 0.5,
        f * 2
      )

  # Math.round: halves toward +infinity.
  defp round_js(x) do
    c = ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end

  # Where a point sits across the dunes' wave: 0 at a trough, rising gently
  # up the windward side to the crest at 0.72, then dropping down the slip
  # face.
  defp phase(x, z) do
    q = (x * 0.9 + z * 0.42 + 26 * fbm(x * 0.014, z * 0.014, 3)) / 19
    q - floor(q)
  end

  # The tall dune the acacia stands on: a sharp crest that snakes toward us
  # from its summit, a gentle face on the town's side and a steep one on the
  # other.
  defp crest_x(z) do
    k = clamp((z - 22) / 52)
    -4 + 26 * k * k * (3 - 2 * k) + 5 * :math.sin((z - 22) * 0.09)
  end

  defp ridge(_x, z) when z < 8, do: 0

  defp ridge(x, z) do
    hc =
      if z <= 74,
        do: 0.5 + 13 * :math.pow(clamp((z - 12) / 62), 1.25),
        else: 13.5 * (1 - (z - 74) / 9)

    dx = x - crest_x(z)
    hc - if(dx < 0, do: -dx * 0.36, else: dx * 0.8)
  end

  defp dunes(x, z) do
    u = phase(x, z)

    prof =
      if u < 0.72,
        do: :math.pow(u / 0.72, 1.5),
        else: :math.pow((1 - u) / 0.28, 0.75)

    rg = ridge(x, z)
    # The field lies low around the big dune so its faces stay clean.
    amp = (1 + 4.5 * fbm(x * 0.008 + 5, z * 0.008, 2)) * (1 - 0.8 * smooth(-3, 3, rg))
    max(prof * amp, rg) + 0.3 * fbm(x * 0.05, z * 0.05, 2)
  end

  defp march(u, v), do: march(u, v, 3, 3, 0)

  defp march(u, v, z, prev, i) when i < 300 and z < 600 do
    y = @cam + v * z

    if v > 0 and y > @hmax do
      0
    else
      gap = y - dunes(u * z, z)

      if gap < 0,
        do: bisect(u, v, prev, z, 0),
        else: march(u, v, z + (max(0.25, gap * 0.5) + z * 0.004), z, i + 1)
    end
  end

  defp march(_u, _v, _z, _prev, _i), do: 0

  defp bisect(_u, _v, _a, b, 7), do: b

  defp bisect(u, v, a, b, j) do
    m = (a + b) / 2

    if @cam + v * m - dunes(u * m, m) < 0,
      do: bisect(u, v, a, m, j + 1),
      else: bisect(u, v, m, b, j + 1)
  end

  defp unit({a, b, c}) do
    n = JSMath.hypot(a, b, c)
    {a / n, b / n, c / n}
  end

  @impl true
  def init(_options) do
    # The town's light comes in low from ahead and to the left; the galaxy's
    # cool fill, from up and to the right.
    light = unit({-0.8, 0.32, 0.5})
    fill = unit({0.6, 0.5, 0.4})

    # --- the dunes, raymarched once -----------------------------------------
    sand =
      List.to_tuple(
        for r <- 0..(@h - 1) do
          v = (@hz - (r + 0.5)) / 100 * @k
          List.to_tuple(for x <- 0..(@w - 1), do: sand_cell(x, v, light, fill))
        end
      )

    top =
      List.to_tuple(
        for x <- 0..(@w - 1) do
          Enum.find(0..(@h - 1), @h, &(elem(elem(sand, &1), x) != nil))
        end
      )

    tree = acacia(elem(top, @acacia))
    mat = fn r, x -> material(sand, tree, r, x) end
    lamps = lamps(top, sand)

    rows =
      for r <- 0..(@h - 1) do
        cells = for x <- 0..(@w - 1), do: frame_static(x, r, mat, elem(elem(sand, r), x), lamps)

        {r, smooth(@h + 1, @h - 12, r + 0.5), cells}
      end

    %{
      rows: rows,
      power: {power_table(@gamma_sky), power_table(@gamma_ground)},
      lut: Palette.nearest_lut(@meta.palette),
      # Set only by the tests: every shortcut a frame takes (the fast powers
      # and the margins that guard them, the glint skipped where it adds
      # nothing, the airglow's shared lattice) is then taken the long way, so
      # the two can be checked against each other.
      exact?: false
    }
  end

  defp sand_cell(x, v, {l0, l1, l2} = light, {g0, g1, g2}) do
    u = (x + 0.5 - 100) / 100 * @k

    case march(u, v) do
      0 ->
        nil

      z ->
        px = u * z
        py = @cam + v * z
        e = 0.2
        hx = (dunes(px + e, z) - dunes(px - e, z)) / (2 * e)
        hz = (dunes(px, z + e) - dunes(px, z - e)) / (2 * e)
        nl = JSMath.hypot(hx, 1, hz)
        nx = -hx / nl
        ny = 1 / nl
        nz = -hz / nl
        lit = max(0, nx * l0 + ny * l1 + nz * l2)
        # A soft shadow: how close the ray to the light passes over the sand.
        lit = if lit > 0, do: lit * clamp(soft_shadow(px, py, z, light, 0.6, 1)), else: lit
        # Faces square to the light stand out.
        lit = min(1, :math.pow(lit, 1.4) * 1.45)
        # Brightest along the crests, shading down each face into the trough.
        ph = phase(px, z)
        rg = ridge(px, z)
        on_ridge = rg >= dunes(px, z) - 0.35
        dxc = px - crest_x(z)

        fall =
          if on_ridge,
            do: 0.5 + 0.5 * :math.exp(-abs(dxc) / 7),
            else: 0.55 + 0.45 * smooth(0.2, 0.72, ph)

        near = 0.72 + 0.28 * smooth(5, 25, z)

        reach =
          (0.55 + 0.45 * :math.exp(-abs(x - @town_x) / 90)) * fall * near *
            smooth(300, 120, z)

        # Starlight from the galaxy's side, and wind ripples across every slope.
        fill = 0.045 * max(0, nx * g0 + ny * g1 + nz * g2)
        ripple = (fbm(px * 0.6 + z * 0.2, z * 0.6, 2) - 0.5) * 0.05
        amb = (0.02 + 0.03 * ny + ripple) * near
        cr = amb * 0.7 + fill * 0.45 + lit * 1.0 * reach
        cg = amb * 0.62 + fill * 0.65 + lit * 0.63 * reach
        cb = amb * 1.35 + fill * 1.2 + lit * 0.53 * reach

        # The big dune's shadowed brink catches a line of starlight.
        {cr, cg, cb} =
          if on_ridge and z < 76 and dxc > 0 do
            cell_w = z * @k * 0.01
            rim = smooth(2.2 * cell_w, 0.6 * cell_w, dxc) * smooth(10, 20, z)
            {cr + 0.1 * rim, cg + 0.14 * rim, cb + 0.24 * rim}
          else
            {cr, cg, cb}
          end

        # Distance thins the light into the horizon's haze.
        haze = clamp(1 - :math.exp(-z / 260)) * mix(0.7, 0.92, smooth(120, 300, z))
        hg = :math.exp(-abs(x - @town_x) / 40) * 0.18
        big = if rg > 0.5 and z < 76, do: smooth(0.9, 0, abs(dxc)), else: 0

        crest =
          max(smooth(0.07, 0, abs(ph - 0.72)) * smooth(260, 30, z), big) *
            (0.3 + 0.7 * smooth(0, 0.2, lit))

        {f32(z), f32(mix(cr, 0.07 + hg, haze)), f32(mix(cg, 0.085 + hg * 0.6, haze)),
         f32(mix(cb, 0.15 + hg * 0.3, haze)), f32(crest)}
    end
  end

  defp soft_shadow(px, py, z, {l0, l1, l2} = light, s, sh) when s < 90 do
    qy = py + l1 * s + 0.05

    if qy > @hmax do
      sh
    else
      sh = min(sh, (qy - dunes(px + l0 * s, z + l2 * s)) / (0.08 * s))
      if sh <= 0, do: sh, else: soft_shadow(px, py, z, light, s + (0.5 + s * 0.05), sh)
    end
  end

  defp soft_shadow(_px, _py, _z, _light, _s, sh), do: sh

  # --- the acacia, on the crest under the galaxy's core ---------------------
  # The cells it covers, as a set of {row, column}.
  defp acacia(base) do
    canopy_top = base - 16
    # Limbs: from the fork up and out to the canopy.
    fork = {@acacia + 0.3, base - 5}

    limbs = [
      {{@acacia, base + 1}, fork, 1.3},
      {fork, {@acacia - 9, canopy_top + 3}, 0.8},
      {fork, {@acacia + 1.5, canopy_top + 2}, 0.75},
      {fork, {@acacia + 10, canopy_top + 3.2}, 0.8},
      {fork, {@acacia - 4, canopy_top + 2.6}, 0.55},
      {{@acacia - 4, base - 9}, {@acacia - 14, canopy_top + 3.5}, 0.55},
      {{@acacia + 3, base - 8}, {@acacia + 15, canopy_top + 3.6}, 0.5}
    ]

    for r <- max(0, canopy_top - 3)..min(base + 1, @h - 1)//1,
        x <- max(0, @acacia - 26)..min(@w - 1, @acacia + 26),
        canopy?(x, x + 0.5, r + 0.5, canopy_top) or
          Enum.any?(limbs, &limb?(&1, x + 0.5, r + 0.5)),
        into: MapSet.new(),
        do: {r, x}
  end

  # An umbrella: a low lumpy dome on top, thinning to the tips, tufts below.
  defp canopy?(x, px, py, canopy_top) do
    q = (px - @acacia) / 17

    if abs(q) > 1.08 do
      false
    else
      top_y = canopy_top + 0.4 + 2.6 * q * q + 1.3 * (noise(px * 0.3, 7.1) - 0.5)

      bot_y =
        canopy_top + 3.8 + 1.4 * (1 - q * q) - 1.4 * smooth(0.8, 1.08, abs(q)) +
          1.2 * (noise(px * 0.45, 3.3) - 0.5) + if(hash(x, 51) < 0.2, do: 0.9, else: 0)

      py > top_y and py < bot_y
    end
  end

  defp limb?({{ax, ay}, {bx, by}, w}, px, py) do
    lx = bx - ax
    ly = by - ay
    t = clamp(((px - ax) * lx + (py - ay) * ly) / (lx * lx + ly * ly))
    dx = px - (ax + lx * t)
    dy = py - (ay + ly * t)
    q = w * (1 - 0.4 * t)
    dx * dx + dy * dy < q * q
  end

  defp material(sand, tree, r, x) do
    cond do
      MapSet.member?(tree, {r, x}) -> :tree
      elem(elem(sand, r), x) == nil -> :sky
      true -> :sand
    end
  end

  # --- the town's lights, a few pinpricks along the far horizon -------------
  # A map from {row, column} to {phase, rate}.
  defp lamps(top, sand) do
    Enum.reduce((@town_x - 9)..(@town_x + 9), [], fn x, lamps ->
      r = elem(top, x)

      cond do
        length(lamps) >= 5 -> lamps
        r >= @h or elem(elem(elem(sand, r), x), 0) < 140 or hash(x, 91) > 0.45 -> lamps
        Enum.any?(lamps, fn {{_, lx}, _} -> abs(lx - x) < 2 end) -> lamps
        true -> lamps ++ [{{r, x}, {hash(x, 92) * 6.28, 0.7 + hash(x, 93) * 1.4}}]
      end
    end)
    |> Map.new()
  end

  # --- the sky: gradient, the town's glow and the milky way ----------------
  # A cell of sky: {r, g, b, airglow, band}, as their Float32Arrays hold them.
  defp sky_cell(x, r) do
    y = r + 0.5
    v = clamp(y / @hz)
    # The town: an amber dome rising from below the horizon, its warmth
    # taking over from the navy rather than greying it.
    tx = x + 0.5 - @town_x
    ty = (y - @town_y) * 1.9
    td = :math.sqrt(tx * tx + ty * ty)
    glow = :math.exp(-td / 16) * 0.4 + :math.exp(-td / 60) * 0.22
    cool = 1 - 0.85 * clamp(:math.exp(-td / 22) * 1.5)
    # A saturated navy, so the dither's specks read as colour.
    cr = (0.02 + 0.03 * v * v) * cool + glow
    cg = (0.035 + 0.045 * v * v) * cool + glow * 0.5
    cb = (0.1 + 0.08 * v * v) * cool + glow * 0.16
    # Airglow, a faint blue sheen low down, kept off the town; it peaks a
    # little above the horizon, where the air below thins it, and varies
    # along the skyline so it never lies as one flat strip.
    along = 0.72 + 0.5 * fbm(x * 0.025 + 3, y * 0.04, 2)

    air =
      :math.pow(smooth(0.3, 0.94, v), 3) * (1 - 0.3 * smooth(0.92, 1.02, v)) * 0.32 * cool *
        along

    # The milky way, along an arc from the core up and over to the west.
    ax = x + 0.5 - @arc_x
    ay = y - @arc_y
    d = :math.sqrt(ax * ax + ay * ay) - @arc_r
    # 0 at the core end.
    s_raw = (@arc_a - :math.atan2(ay, ax)) / @arc_s
    s = clamp(s_raw)
    # The band ends at the core.
    {fin, lane_end} =
      if s_raw < 0 do
        q1 = s_raw / 0.05
        q2 = s_raw / 0.11
        {:math.exp(-(q1 * q1)), :math.exp(-(q2 * q2))}
      else
        {1, 1}
      end

    w = 9 + 8 * :math.pow(1 - s, 1.4)
    lane0 = (noise(s * 9, 3.3) - 0.5) * w * 0.5 * smooth(0, 0.25, s)
    dw = d / w
    b = :math.exp(-(dw * dw))
    clump = fbm(x * 0.09, y * 0.09, 4)
    b = b * (0.35 + 1.1 * smooth(0.3, 0.75, clump))
    b = b * ((0.55 + 0.55 * (1 - s)) * fin)
    # The core's bulge.
    cx = x + 0.5 - @core_x
    cy = (y - @core_y) * 1.3
    cd = :math.sqrt(cx * cx + cy * cy)
    core = :math.exp(-cd / 6) * 0.5 + :math.exp(-cd / 22) * 0.25
    b = b + core
    # The dust lane, a crisp rift through the bulge, and its filaments.
    near_core = :math.exp(-cd / 16)
    ql = (d - lane0) / (w * 0.12)

    lane =
      :math.exp(-(ql * ql)) *
        mix((0.55 + 0.6 * fbm(x * 0.12, y * 0.12, 3)) * (0.55 + 0.45 * (1 - s)), 1, near_core) *
        lane_end

    fil = smooth(0.58, 0.78, fbm(x * 0.16 + 9, y * 0.16, 3)) * 0.6
    qf = d / (w * 1.3)
    b = b * (clamp(1 - mix(0.92, 0.97, near_core) * lane) * (1 - fil * :math.exp(-(qf * qf))))
    qb = d / (w * 1.2)
    band = :math.exp(-(qb * qb)) * fin + core
    # Warm toward the core, cool along the arm.
    warm = clamp(:math.exp(-cd / 26) * 1.2 + (1 - s) * 0.25)

    {f32(cr + b * mix(0.62, 1.0, warm) * 0.75), f32(cg + b * mix(0.68, 0.9, warm) * 0.75),
     f32(cb + b * mix(0.95, 0.74, warm) * 0.75), f32(air), f32(band)}
  end

  # Everything about a cell that does not move: its colour, what the frame
  # adds to it, its dither and its floor.
  defp frame_static(x, r, mat, sand, lamps) do
    bay = elem(@bayer, band(r, 3) * 4 + band(x, 3))

    case mat.(r, x) do
      :sky ->
        {kr, kg, kb, air, band} = sky_cell(x, r)
        # The band and the glow low down get a wider, half-ordered dither, so
        # their gradients fade out instead of stopping at an edge: random in
        # open sky, half ordered in the band.
        inb = clamp(band)
        soft = max(inb, clamp(air / 0.2))
        rnd = (hash(x * 3 + 1, r * 5 + 2) - 0.5) * mix(0.6, 0.94, soft)
        air = if r >= @air0 and r < @hz + 2, do: air
        {:sky, kr, kg, kb, air, star(x, r, inb), f32(mix(rnd, bay, 0.5 * soft)), f32(0.1 * inb)}

      :tree ->
        # Warm light from the core caught on the canopy's top, where the
        # canopy's upper edge is rimmed by the bulge behind it.
        e =
          if r >= 1 and mat.(r - 1, x) == :sky do
            dx = x + 0.5 - @core_x
            dy = (r - @core_y) * 1.3
            f32(0.25 + 0.75 * :math.exp(-:math.sqrt(dx * dx + dy * dy) / 18))
          else
            0
          end

        {:fixed, f32(e * 0.42), f32(e * 0.3), f32(e * 0.2), if(e > 0, do: @f01, else: 0.0),
         f32(bay), false}

      :sand ->
        {_z, sr, sg, sb, crest} = sand

        case lamps do
          %{{^r, ^x} => {ph, rate}} ->
            {:lamp, ph, rate, f32(bay)}

          _ ->
            # Sand glinting along the brink of each slip face.
            glint =
              if crest > 0 do
                h = hash(r * @w + x, 5)
                {crest, 0.8 + 2.2 * h, h * 40}
              end

            {:sand, sr, sg, sb, glint, f32(bay)}
        end
    end
  end

  # --- stars: thick in the band, a few bright ones everywhere ---------------
  defp star(x, r, inb) when r < @hz + 2 do
    if hash(x * 7 + 3, r * 13 + 1) > 0.015 + 0.12 * inb do
      nil
    else
      m = :math.pow(hash(x * 5 + 1, r * 3 + 7), 12)
      bright = (0.2 + 0.95 * m) * smooth(@hz + 1, @hz - 6, r + 0.5)
      c = hash(x * 11, r * 17 + 5)

      tint =
        cond do
          c < 0.2 -> {0.78, 0.86, 1}
          c < 0.9 -> {1, 1, 1}
          true -> {1, 0.82, 0.6}
        end

      {bright, tint, 1.5 + hash(x, r * 9) * 4, hash(r, x * 3) * 6.28}
    end
  end

  defp star(_x, _r, _inb), do: nil

  # Meteor 0 is already falling; meteor n starts somewhere in its 7 second
  # slot, and heads across the sky rather than straight off its nearer edge.
  defp meteor(0), do: {-0.35, 199, 4, :math.cos(2.65), :math.sin(2.65), 52 + hash(0, 76) * 30}

  defp meteor(n) do
    x0 = 30 + hash(n, 72) * 140
    a = if(x0 > 100, do: 2.6, else: 0.55) + (hash(n, 75) - 0.5) * 0.4

    {7 * (n - 1) + 2.5 + hash(n, 71) * 2.5, x0, 4 + hash(n, 73) * 18, :math.cos(a), :math.sin(a),
     52 + hash(n, 76) * 30}
  end

  @impl true
  def frame(state, t, env) do
    # The airglow drifts slowly along the horizon.
    {cols, base} = drift_columns(t, state.exact?)

    base_rows =
      List.to_tuple(
        for {r, _edge, cells} <- state.rows do
          glow = if r >= @air0 and r < @hz + 2, do: drift_row(base, r * 0.08)
          cells |> base_cells(0, glow, cols, {t, state.exact?}, []) |> List.to_tuple()
        end
      )

    over =
      t
      |> meteors(base_rows)
      |> Enum.group_by(fn {k, _} -> div(k, @w) end, fn {k, v} -> {rem(k, @w), v} end)

    acc = {<<>>, <<>>, state.lut, env.color?, if(state.exact?, do: :exact, else: state.power)}

    {text, colors, lut, color?, _} =
      Enum.reduce(state.rows, acc, fn {r, edge, _cells}, acc ->
        overlays = over |> Map.get(r, []) |> Enum.sort()
        acc = dots_row(Tuple.to_list(elem(base_rows, r)), 0, overlays, edge, acc)
        if r < @h - 1, do: newline(acc), else: acc
      end)

    {text, if(color?, do: colors), %{state | lut: lut}}
  end

  defp newline({text, colors, lut, color?, power}),
    do: {<<text::binary, ?\n>>, colors, lut, color?, power}

  # The airglow's noise at ((x - 0.3 t) * 0.03, r * 0.08): each column's
  # lattice cell and blend once a frame, each row's corner hashes once.
  defp drift_columns(t, true),
    do: {List.to_tuple(for(x <- 0..(@w - 1), do: {(x - t * 0.3) * 0.03, nil})), :exact}

  defp drift_columns(t, false) do
    cols =
      for x <- 0..(@w - 1) do
        v = (x - t * 0.3) * 0.03
        xi = floor(v)
        fx = v - xi
        {xi, fx * fx * (3 - 2 * fx)}
      end

    {base, _} = hd(cols)
    {last, _} = List.last(cols)
    {List.to_tuple(for {xi, u} <- cols, do: {xi - base, u}), {base, last - base}}
  end

  defp drift_row(:exact, y), do: {:at, y}

  defp drift_row({base, n}, y) do
    yi = floor(y)
    fy = y - yi

    {List.to_tuple(for i <- 0..(n + 1), do: hash(base + i, yi)),
     List.to_tuple(for i <- 0..(n + 1), do: hash(base + i, yi + 1)), fy * fy * (3 - 2 * fy)}
  end

  # noise/2 from its lattice, or noise/2 itself, the long way.
  defp drift({:at, y}, {x, nil}), do: noise(x, y)

  defp drift({lo, hi, v}, {i, u}) do
    a = elem(lo, i)
    b = elem(lo, i + 1)
    c = elem(hi, i)
    d = elem(hi, i + 1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  defp base_cells([], _x, _glow, _cols, _t, acc), do: :lists.reverse(acc)

  defp base_cells([cell | cells], x, glow, cols, t, acc),
    do: base_cells(cells, x + 1, glow, cols, t, [base_cell(cell, x, glow, cols, t) | acc])

  defp base_cell({:sky, kr, kg, kb, air, star, dith, floor}, x, glow, cols, {t, _exact?}) do
    {cr, cg, cb} =
      if air != nil and glow != nil do
        a = air * (0.86 + 0.28 * drift(glow, elem(cols, x)))
        {f32(kr + a * 0.3), f32(kg + a * 0.5), f32(kb + a * 1.2)}
      else
        {kr, kg, kb}
      end

    case star do
      nil ->
        {cr, cg, cb, floor, dith, true}

      {b, {t0, t1, t2}, rate, ph} ->
        tw =
          if b > 0.35,
            do: 0.72 + 0.28 * :math.sin(t * rate + ph),
            else: 0.6 + 0.4 * :math.sin(t * rate + ph)

        s = b * tw
        {f32(cr + s * t0), f32(cg + s * t1), f32(cb + s * t2), @f028, dith, true}
    end
  end

  defp base_cell({:sand, sr, sg, sb, glint, dith}, _x, _glow, _cols, {t, exact?}) do
    case glint do
      nil ->
        {sr, sg, sb, @f002, dith, false}

      {c, speed, phase} ->
        w = :math.sin(t * speed + phase)

        if w > 0 or exact? do
          g = c * :math.pow(max(0, w), 8) * 0.5
          {f32(sr + g), f32(sg + g * 0.85), f32(sb + g * 0.7), @f002, dith, false}
        else
          # pow(0, 8) is 0: the glint adds nothing.
          {sr, sg, sb, @f002, dith, false}
        end
    end
  end

  defp base_cell({:lamp, ph, rate, dith}, _x, _glow, _cols, {t, _exact?}) do
    g = 0.42 + 0.14 * :math.sin(t * rate + ph) * :math.sin(t * rate * 2.3 + ph * 3)
    {f32(g), f32(0.85 * g), f32(0.66 * g), @f012, dith, false}
  end

  defp base_cell({:fixed, cr, cg, cb, floor, dith, sky?}, _x, _glow, _cols, _t),
    do: {cr, cg, cb, floor, dith, sky?}

  # A meteor, if one is crossing: the cells of its trail, in order, over the
  # sky.
  defp meteors(t, base_rows) do
    n = floor((t - 2.5) / 7) + 1

    Enum.reduce(max(0, n - 1)..(n + 1)//1, %{}, fn i, over ->
      {start, x0, y0, dx, dy, speed} = meteor(i)
      age = t - start

      if age < 0 or age > 0.9 do
        over
      else
        fade_in = smooth(0, 0.12, age)
        fade_out = smooth(0.9, 0.6, age)
        hx = x0 + dx * speed * age
        hy = y0 + dy * speed * age * 0.75
        len = min(28, speed * age)

        Stream.iterate(0, &(&1 + 1))
        |> Stream.take_while(&(&1 < len * 2))
        |> Enum.reduce(over, fn j, over ->
          f = j / (len * 2)
          px = round_js(hx - dx * f * len)
          py = round_js(hy - dy * f * len * 0.75)
          trail(over, base_rows, px, py, (1 - f) * fade_in * fade_out * 1.25)
        end)
      end
    end)
  end

  defp trail(over, base_rows, px, py, s) when px >= 0 and px < @w and py >= 0 and py < @h do
    k = py * @w + px

    {cr, cg, cb, fl, dith, sky?} =
      case over do
        %{^k => cell} -> cell
        _ -> elem(elem(base_rows, py), px)
      end

    if sky? do
      Map.put(
        over,
        k,
        {f32(max(cr, s * 0.9)), f32(max(cg, s * 0.96)), f32(max(cb, s)),
         f32(max(fl, if(s > 0.12, do: 0.4, else: 0))), dith, true}
      )
    else
      over
    end
  end

  defp trail(over, _base_rows, _px, _py, _s), do: over

  defp dots_row([], _x, _overlays, _edge, acc), do: acc

  defp dots_row([cell | cells], x, overlays, edge, acc) do
    {{cr, cg, cb, fl, dith, sky?}, overlays} =
      case overlays do
        [{^x, over} | rest] -> {over, rest}
        _ -> {cell, overlays}
      end

    acc = dot(cr, cg, cb, fl, edge, dith, sky?, acc)
    dots_row(cells, x + 1, overlays, edge, acc)
  end

  # Each cell is one dot, in the palette colour nearest its hue.
  #
  # Math.pow is slow, so the level is first found with power/2, within
  # 1e-13 of pow(peak, 0.92) in the sky and pow(peak, 0.75) elsewhere. Every
  # decision the level feeds (the dot's rounding, the colour's step in the
  # cache, a cache miss) is then checked: when one sits within 1e-8 of its
  # threshold, or the colour is not cached yet, the cell is worked out again
  # with :math.pow, so the result is always upstream's.
  defp dot(cr, cg, cb, fl, edge, dith, sky?, {_, _, _, _, :exact} = acc) do
    gamma = if sky?, do: @gamma_sky, else: @gamma_ground
    exact_dot(cr, cg, cb, {fl, edge, dith, gamma}, cr |> max(cg) |> max(cb) |> max(1.0e-4), acc)
  end

  defp dot(cr, cg, cb, fl, edge, dith, sky?, {text, colors, lut, color?, powers} = acc) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    power = elem(powers, if(sky?, do: 0, else: 1))
    level = clamp(fl + (1 - fl) * power(peak, power)) * edge
    v = level * 3 + dith
    whole = floor(v)
    f = v - whole

    if abs(f - 0.5) < @margin do
      exact_dot(cr, cg, cb, {fl, edge, dith, elem(power, 0)}, peak, acc)
    else
      # Math.round, away from the half.
      step = if f < 0.5, do: whole, else: whole + 1
      step = max(0, min(3, step))
      text = <<text::binary, elem(@dots, step)::binary>>

      case color? && cached(lut, tint(cr, cg, cb, level, step, peak)) do
        false ->
          {text, colors, lut, false, powers}

        nil ->
          exact_color(
            cr,
            cg,
            cb,
            {fl, edge, dith, elem(power, 0)},
            peak,
            {text, colors, lut, true, powers}
          )

        index ->
          {text, <<colors::binary, index>>, lut, true, powers}
      end
    end
  end

  # x^gamma for 2^-20 <= x < 2^12: x is m * 2^e with m in [1, 2), so it is
  # c^gamma * (1 + d)^gamma * 2^(gamma e), where c is the middle of m's
  # 128th of [1, 2) and |d| <= 1/256. The first and last come from tables,
  # the middle from its binomial series to the d^4 term, which leaves under
  # 2e-14 out. Outside that range it is :math.pow.
  defp power_table(gamma) do
    mant =
      List.to_tuple(
        for i <- 0..127 do
          c = 1 + (i + 0.5) / 128
          # 2^-52 / c turns m - c, counted in units of 2^-52, into d.
          {2.220446049250313e-16 / c, :math.pow(c, gamma)}
        end
      )

    exps = List.to_tuple(for e <- @power_lo..11, do: :math.pow(2.0, gamma * e))
    k2 = gamma * (gamma - 1) / 2
    k3 = k2 * (gamma - 2) / 3
    {gamma, mant, exps, k2, k3, k3 * (gamma - 3) / 4}
  end

  defp power(x, {gamma, mant, exps, k2, k3, k4}) do
    <<_::1, be::11, hi::7, rest::45>> = <<x::float>>
    i = be - 1023 - @power_lo

    if i >= 0 and i < tuple_size(exps) do
      {scale, base} = elem(mant, hi)
      d = (rest - 0x100000000000) * scale
      base * (1 + d * (gamma + d * (k2 + d * (k3 + d * k4)))) * elem(exps, i)
    else
      :math.pow(x, gamma)
    end
  end

  defp tint(cr, cg, cb, level, step, peak) do
    want = if step != 0, do: min(1, (level + 0.06) / elem(@cover, step)), else: 0
    s = (0.3 + 0.7 * want) / peak
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

  defp exact_level({fl, edge, _dith, gamma}, peak),
    do: clamp(fl + (1 - fl) * :math.pow(peak, gamma)) * edge

  defp exact_dot(cr, cg, cb, {_, _, dith, _} = cell, peak, {text, colors, lut, color?, powers}) do
    level = exact_level(cell, peak)
    step = max(0, min(3, round_js(level * 3 + dith)))
    text = <<text::binary, elem(@dots, step)::binary>>

    if color? do
      {r, g, b} = tint(cr, cg, cb, level, step, peak)
      {index, lut} = Palette.nearest(lut, r, g, b)
      {text, <<colors::binary, index>>, lut, true, powers}
    else
      {text, colors, lut, false, powers}
    end
  end

  # The colour alone, worked out exactly; the dot is already drawn.
  defp exact_color(cr, cg, cb, {_, _, dith, _} = cell, peak, {text, colors, lut, true, powers}) do
    level = exact_level(cell, peak)
    step = max(0, min(3, round_js(level * 3 + dith)))
    {r, g, b} = tint(cr, cg, cb, level, step, peak)
    {index, lut} = Palette.nearest(lut, r, g, b)
    {text, <<colors::binary, index>>, lut, true, powers}
  end
end
