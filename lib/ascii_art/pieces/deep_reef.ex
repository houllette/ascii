defmodule AsciiArt.Pieces.DeepReef do
  @moduledoc """
  Light shafts, swaying kelp and a turning school of fish over a reef.

  Looking along a coral reef from a few metres down. The sun is a bright
  blaze in the rippled surface, shafts of light fan down from it, kelp sways
  in the swell, a school of fish wheels through the dark water, bubbles rise
  and caustics crawl over the sand.

  The water, the sand and the reef are shaded once; each frame adds the
  light that moves (shafts, ripples, caustics) and draws what swims or sways
  on top. Every cell is then a halftone dot sized by its brightness,
  ordered-dithered, in the palette colour nearest its hue.

  Ported from `src/pieces/deep-reef.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Palette, Rand}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "deep reef",
    category: :scenes,
    note: "light shafts, swaying kelp and a turning school of fish over a reef",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#03101a",
    # A dot is never drawn darker than about half brightness (dot size
    # carries the darkness), so the palette starts at mid tones.
    palette: [
      "#114a66",
      "#165c78",
      "#1d708a",
      "#27869b",
      "#3a9fae",
      "#58b9c0",
      "#80d2d2",
      "#b0e8e2",
      "#e2fbf5",
      "#5e6b62",
      "#87927f",
      "#aab39a",
      "#cfd2b4",
      "#38461a",
      "#5a6420",
      "#857f2a",
      "#b0a03c",
      "#d6c25a",
      "#efe08e",
      "#8e3355",
      "#c4506a",
      "#e0786e",
      "#f0a070",
      "#6a3a78",
      "#9a5aa8",
      "#c88ad0",
      "#6f8a98",
      "#9fb8c6",
      "#cfe3ea"
    ]
  }

  @w 200
  @h 100
  # The surface band.
  @surf 15
  # Where the sea floor would meet the haze.
  @hz 61
  # Where the sun shows through the surface.
  @sun_x 136
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()

  @none 0
  @sand 1
  @reef 2
  @far 3
  @fan 4

  # The caustics' tile, and the cells of its Voronoi web.
  @ct 64
  @cc 6
  @cs @ct / @cc

  # Shafts fan out from the sun, above the frame; the one straight down.
  @sun_y -12
  @rays 320
  @ray0 160

  @coral {{0.86, 0.36, 0.44}, {0.93, 0.55, 0.3}, {0.6, 0.36, 0.72}, {0.78, 0.7, 0.35}}
  @rock {0.016, 0.03, 0.042}
  # Brain corals, domes on the crests: {x, depth of the centre below the
  # crest, radius, kind}.
  @domes [
    {16, 3, 7, 0},
    {41, 2.5, 6.5, 1},
    {53, 2, 4.5, 3},
    {65, 2, 5, 2},
    {158, 2, 4, 2},
    {186, 3, 5, 1},
    {196, 3, 4.5, 3}
  ]
  # Small coral heads out on the sand: {x, crest row, half width, fog, kind}.
  @bommies [{114, 69, 9, 0.18, 0}, {94, 63.6, 4, 0.5, 2}, {139, 64.4, 4, 0.42, 1}]
  @fan_x 167
  @fan_r 27
  # Kelp: {x, base row, length, width, phase, how much water hides it}.
  @kelp [{14, 100, 96, 3.5, 0.0, 0}, {189, 100, 96, 3.5, 5.2, 0}]
  @streams [{44, 52, 8}, {168, 66, 7}, {116, 96, 6}]

  @gamma 0.85
  @power_lo -20
  @margin 1.0e-8
  @f32_margin 1.0e-11
  @mul_lo band(1_274_126_177, 0xFFFF)
  <<floor_solid::float-32>> = <<0.02::float-32>>
  # The floor under everything but open water, as its Float32Array holds 0.02.
  @floor_solid floor_solid

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
            power: 2,
            wrap: 1,
            sure?: 1}
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

  # The scenes' hash (`AsciiArt.Kit.Hash.scene/2`) of two integers, inlined:
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

  # Value noise (`AsciiArt.Kit.Scene.noise/3` with no period), with the four
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

  # Math.round: halves toward +infinity.
  defp round_js(x) do
    c = ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end

  # Both reefs are rounded masses, shouldering down toward the open sand.
  defp dome(u), do: 1 - :math.sqrt(max(0, 1 - u * u))

  defp left_top(x),
    do: 47 + 56 * dome(min(1, x / 86)) - 8 * fbm(x * 0.06, 3.1, 4) + 3 * max(0, (10 - x) / 10)

  defp right_top(x) do
    q = (x - 191) / 6
    69 + 34 * dome(min(1, (196 - x) / 48)) - 5 * fbm(x * 0.08, 8.3, 3) - 3 * :math.exp(-(q * q))
  end

  defp far_top(x) do
    q = (x - 120) / 18
    @hz - 1 - 6 * fbm(x * 0.035 + 2, 1.7, 3) - 3 * :math.exp(-(q * q))
  end

  @impl true
  def init(_options) do
    caus = caustics()
    tops = List.to_tuple(for x <- 0..(@w - 1), do: {left_top(x), right_top(x), far_top(x)})

    domes =
      for {x, d, r, kind} <- @domes,
          do: {x, if(x < 100, do: left_top(x), else: right_top(x)) + d, r, kind}

    fan_y = right_top(@fan_x) + 1.5

    scene =
      for r <- 0..(@h - 1), x <- 0..(@w - 1), into: %{} do
        {r * @w + x, scene_cell(x, r, elem(tops, x), domes, fan_y)}
      end

    scene = branches(scene)
    water = water()
    {fish, bubbles, snow} = movers()

    rows =
      for r <- 0..(@h - 1) do
        # How far down a shaft has faded.
        depth_fade = :math.exp(-r / 30) * smooth(0, 14, r + 6)

        cells =
          for x <- 0..(@w - 1) do
            k = r * @w + x
            base_static(x, r, Map.fetch!(scene, k), elem(water, k))
          end

        {r, r + 0.5, depth_fade, surface_row(r), cells}
      end

    %{
      rows: rows,
      caus: caus,
      fish: fish,
      bubbles: bubbles,
      snow: snow,
      kelp: kelp_static(),
      ray_at: List.to_tuple(for k <- 0..(@w * @h - 1), do: elem(elem(water, k), 3)),
      shafts: List.to_tuple(for u <- 0..(@rays - 1), do: shaft_static(u)),
      power: power_table(@gamma),
      ripple: power_table(1.6),
      lut: Palette.nearest_lut(@meta.palette),
      # Set only by the tests: every shortcut a frame takes (the fast powers
      # and the margins that guard them, the caustics' cheaper wrap) is then
      # taken the long way, so the two can be checked against each other.
      exact?: false
    }
  end

  # --- caustics: a tiling web of bright lines (cell edges of a Voronoi) -----
  defp caustics do
    {pts, _} =
      for j <- 0..(@cc - 1), i <- 0..(@cc - 1), reduce: {[], Rand.seed(7)} do
        {pts, rand} ->
          {a, rand} = Rand.next(rand)
          {b, rand} = Rand.next(rand)
          {[{(i + 0.15 + 0.7 * a) * @cs, (j + 0.15 + 0.7 * b) * @cs} | pts], rand}
      end

    pts = Enum.reverse(pts)

    offsets =
      for {px, py} <- pts, oy <- [-@ct, 0, @ct], ox <- [-@ct, 0, @ct], do: {px, py, ox, oy}

    List.to_tuple(
      for y <- 0..(@ct - 1), x <- 0..(@ct - 1) do
        {f1, f2} =
          Enum.reduce(offsets, {1.0e9, 1.0e9}, fn {px, py, ox, oy}, {f1, f2} ->
            dx = x + 0.5 - px - ox
            dy = y + 0.5 - py - oy
            d = :math.sqrt(dx * dx + dy * dy)

            cond do
              d < f1 -> {d, f1}
              d < f2 -> {f1, d}
              true -> {f1, f2}
            end
          end)

        f32(:math.pow(1 - smooth(0, 0.42 * @cs, f2 - f1), 2.2))
      end
    )
  end

  # ((u % 64) + 64) % 64 the long way, for the tests.
  defp caus_at({:fmod, caus}, u, v),
    do:
      caus_cell(
        caus,
        :math.fmod(:math.fmod(u, 64.0) + 64, 64.0),
        :math.fmod(:math.fmod(v, 64.0) + 64, 64.0)
      )

  defp caus_at(caus, u, v),
    do: caus_cell(caus, wrap(:math.fmod(u, 64.0) + 64), wrap(:math.fmod(v, 64.0) + 64))

  defp caus_cell(caus, u, v) do
    x0 = trunc(u)
    y0 = trunc(v)
    ax = u - x0
    ay = v - y0
    x1 = rem(x0 + 1, @ct)
    y1 = rem(y0 + 1, @ct)
    a = elem(caus, y0 * @ct + x0)
    b = elem(caus, y0 * @ct + x1)
    c = elem(caus, y1 * @ct + x0)
    d = elem(caus, y1 * @ct + x1)
    a + (b - a) * ax + (c - a) * ay + (a - b - c + d) * ax * ay
  end

  # `% 64` of a sum in [0, 128): exact either way.
  defp wrap(s) when s >= 64, do: s - 64
  defp wrap(s), do: s

  # --- the water: deep navy, lit from the surface and the sun ----------------
  defp water do
    List.to_tuple(
      for r <- 0..(@h - 1), x <- 0..(@w - 1) do
        v = (r + 0.5) / @h
        up = :math.pow(1 - v, 2.2)
        q1 = (x - @sun_x) / 52
        q2 = (r - 4) / 34
        sun = :math.exp(-(q1 * q1) - q2 * q2)
        # Looking level, the distance is a lit blue haze the reefs stand
        # against.
        q3 = (r - 54) / 15
        haze = :math.exp(-(q3 * q3)) * (1 - 0.6 * smooth(30, 100, abs(x - 112)))
        # Darker toward the sides and the floor, but the upper water stays lit
        # so the kelp stands dark against it.
        edge =
          1 - 0.4 * smooth(50, 104, abs(x - 112)) * smooth(8, 70, r) - 0.3 * smooth(66, 100, r)

        # Soft clouds of plankton haze, so open water is never one flat tone.
        veil = 0.78 + 0.44 * fbm(x * 0.022 + 5, r * 0.04, 4)
        # Which shaft the cell sits in.
        a = :math.atan2(x + 0.5 - @sun_x, r + 0.5 - @sun_y)

        {f32((0.012 + 0.09 * up + 0.05 * sun + 0.04 * haze) * edge * veil),
         f32((0.1 + 0.32 * up + 0.14 * sun + 0.15 * haze) * edge * veil),
         f32((0.15 + 0.27 * up + 0.12 * sun + 0.17 * haze) * edge * veil),
         max(0, min(@rays - 1, round_js((a + 1.6) * 100)))}
      end
    )
  end

  # --- the static scene: sand, the reef, a far reef in the haze, a sea fan --
  # Each cell is {material, lit colour r, g, b, the water between us and it,
  # caustic coordinates u, v, and their weight}, painted layer over layer.
  defp scene_cell(x, r, {left, right, far}, domes, fan_y) do
    y = r + 0.5

    {@none, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
    |> sea_floor(x, r, y)
    |> far_reef(x, r, y, far)
    |> sea_fan(x, r, y, fan_y)
    |> bommies(x, y)
    |> reef_mass(x, r, y, if(x < 100, do: left, else: right))
    |> domes(x, y, domes)
  end

  # The sea floor, a plane running off into the haze.
  defp sea_floor(_cell, x, r, y) when r >= @hz + 2 do
    d = y - @hz
    z = 300 / d
    # The floor is seen at a low angle, so its pattern squeezes toward the
    # haze; spacing grows as it comes nearer, and fades out before it gets
    # too fine to draw.
    near = 0.4 + 0.6 * (d / 38)
    sx = (x + 0.5 - 100) / near
    sy = 30 * :math.log(d)
    aa = smooth(2.2, 1.4, 30 / d)
    # Ripples in the sand run across our view, bending a little: thin bright
    # crests over darker troughs.
    ph = sy + 7 * fbm(sx * 0.07, sy * 0.06, 2) + sx * 0.05

    crest =
      :math.pow(0.5 + 0.5 * :math.sin(ph), 3) *
        smooth(0.3, 0.6, fbm(sx * 0.09 + 7, sy * 0.12, 2))

    rip = 0.74 + aa * (0.5 * crest - 0.12) + 0.12 * (fbm(sx * 0.08, sy * 0.15, 3) - 0.5)
    lit = 0.6 + 0.15 * smooth(100, 130, x) - 0.3 * smooth(84, 100, r)

    {@sand, f32(0.38 * rip * lit), f32(0.37 * rip * lit), f32(0.3 * rip * lit),
     f32(1 - :math.exp(-z / 40)), f32(sx * 0.9), f32(sy * 2.3), f32(0.5 * smooth(14, 26, d))}
  end

  defp sea_floor(cell, _x, _r, _y), do: cell

  # Lit along its crest, dim below, half lost in the blue.
  defp far_reef({_, _, _, _, _, cu, cv, _} = cell, x, r, y, far) do
    if y >= far and r < @hz + 6 do
      s = (0.45 + 0.55 * fbm(x * 0.15, y * 0.15, 2)) * (0.5 + 0.8 * :math.exp(-(y - far) / 2))
      {@far, f32(0.06 * s), f32(0.11 * s), f32(0.14 * s), f32(0.68), cu, cv, 0.0}
    else
      cell
    end
  end

  # The sea fan: a thin lattice of veins spreading up from its root.
  defp sea_fan({_, _, _, _, _, cu, cv, _} = cell, x, r, y, fan_y) do
    dx = x + 0.5 - @fan_x
    dy = fan_y - y
    a = :math.atan2(dx, dy)

    with true <- dy > -1 and abs(a) < 1.2,
         d = JSMath.hypot(dx, dy),
         reach = @fan_r * (0.68 + 0.36 * fbm(a * 2.6 + 5, 1, 3)),
         true <- d < reach do
      aw = a + 0.08 * (fbm(d * 0.2, a * 2, 2) - 0.5) * 4
      ray = abs(JSMath.mod(aw * 7.5 / :math.pi() + 100, 1) - 0.5)
      ring = abs(JSMath.mod(d / 3.2 + 100, 1) - 0.5)
      mesh = hash(x * 3, r * 5) < 0.08

      vein =
        ray > 0.42 or (ring > 0.45 and d > 5) or mesh or (d < 4 and abs(dx) < 1.2) or
          d > reach - 1.2

      # Dark at the root, catching the light toward its rim; between the
      # veins a thin dim web the water shows through.
      o = smooth(2, reach, d)
      s = (0.35 + 0.75 * o) * if(vein, do: 1, else: 0.22)

      {@fan, f32(mix(0.32, 0.72, o) * s), f32(mix(0.12, 0.38, o) * s), f32(mix(0.38, 0.8, o) * s),
       f32(if(vein, do: 0.2, else: 0.4)), cu, cv, 0.0}
    else
      _ -> cell
    end
  end

  # Small coral heads out on the sand, half lost in the blue.
  defp bommies(cell, x, y) do
    Enum.reduce(@bommies, cell, fn {bx, crest, hw, f0, kind}, cell ->
      u = (x + 0.5 - bx) / hw
      top = crest + u * u * u * u * hw * 0.5 - 1.6 * fbm(x * 0.35, crest, 2)

      if abs(u) < 1.1 and y >= top and
           y < crest + hw * 0.5 + 1.5 * fbm(x * 0.3, crest + 5, 2) - 0.6 * u * u do
        below = y - top
        living = smooth(2.2, 0.6, below) * smooth(0.45, 0.6, fbm(x * 0.25 + bx, y * 0.3, 2))
        lit = 0.3 + 0.6 * :math.exp(-below / 1.5)
        {cr0, cg0, cb0} = elem(@coral, kind)
        {r0, g0, b0} = @rock

        {@reef, f32(mix(r0, cr0, living) * lit), f32(mix(g0, cg0, living) * lit),
         f32(mix(b0, cb0, living) * lit), f32(f0), f32(x * 0.5), f32(y * 0.9),
         f32(0.5 * :math.exp(-below / 1.5))}
      else
        cell
      end
    end)
  end

  # Reef masses, left and right: dark rock, rimmed with lit coral.
  defp reef_mass(cell, x, r, y, top) do
    if y >= top and (x < 87 or x > 147) do
      below = y - top
      n = fbm(x * 0.18, y * 0.22, 4)
      # Lumps of rock and coral heads, each lit on its upper side.
      lump = fbm(x * 0.07, y * 0.1, 3)
      lump_up = fbm(x * 0.07, (y - 1.5) * 0.1, 3)
      face = clamp(0.5 + (lump_up - lump) * 14)

      lit =
        (0.25 + 0.5 * face + 0.6 * :math.exp(-below / 5) + 0.14 * (n - 0.5)) *
          (0.55 + 0.45 * smooth(100, 40, r))

      # Patches of living coral, thick along the crest, a few sponges below.
      kind = rem(floor(fbm(x * 0.06 + 11, y * 0.09, 3) * 7), 4)
      patch = fbm(x * 0.12 + 4, y * 0.12, 3)

      living =
        max(
          smooth(0.44, 0.56, patch) * smooth(7, 1.5, below),
          smooth(0.66, 0.72, patch) * 0.35 * smooth(24, 6, below)
        )

      {cr0, cg0, cb0} = elem(@coral, kind)
      # A cool rim of light along the bare rock of the crest, and the upper
      # lips of ledges down the face catch a little of it.
      rim = smooth(2.4, 0.3, below) * 0.6
      ledge = smooth(0.66, 0.9, face) * smooth(3, 8, below) * 0.55
      {r0, g0, b0} = @rock
      rr = mix(mix(r0, 0.05, ledge), 0.12, rim)
      rg = mix(mix(g0, 0.11, ledge), 0.24, rim)
      rb = mix(mix(b0, 0.13, ledge), 0.25, rim)

      {@reef, f32(mix(rr, cr0, living) * lit), f32(mix(rg, cg0, living) * lit),
       f32(mix(rb, cb0, living) * lit),
       f32(if(x < 100, do: 0.04 + 0.04 * smooth(0, 80, x), else: 0.08)), f32(x * 0.5),
       f32(y * 0.9), f32(0.8 * :math.exp(-below / 1.5))}
    else
      cell
    end
  end

  # Brain corals on the crests.
  defp domes(cell, x, y, domes) do
    Enum.reduce(domes, cell, fn {dx0, dy0, dr, kind}, cell ->
      dx = x + 0.5 - dx0
      dy = y - dy0
      d = JSMath.hypot(dx, dy * 1.25)

      if d < dr and dy < dr * 0.3 do
        q = d / dr
        nz = :math.sqrt(max(0, 1 - q * q))
        lamb = clamp(0.15 + 0.85 * (nz * 0.6 - dy / dr * 0.55 + dx / dr * 0.25))
        groove = 0.75 + 0.25 * :math.sin(d * 2.4 + 2 * fbm(x * 0.3, y * 0.3, 2) * 3)
        {cr0, cg0, cb0} = elem(@coral, rem(kind + 1, 4))
        s = (0.15 + 0.9 * lamb) * groove

        {@reef, f32(cr0 * s), f32(cg0 * s), f32(cb0 * s),
         f32(if(dx0 < 100, do: 0.04 + 0.04 * smooth(0, 80, dx0), else: 0.08)), f32(x * 0.5),
         f32(y * 0.9), f32(0.5 * clamp(-dy / dr + 0.6))}
      else
        cell
      end
    end)
  end

  # Branching coral standing up off both crests.
  defp branches(scene) do
    scene
    |> branch_set(31, 10, 3, 60, &left_top/1)
    |> branch_set(53, 3, 178, 20, &right_top/1)
  end

  defp branch_set(scene, seed, count, x0, span, top_at) do
    {scene, _} =
      Enum.reduce(0..(count - 1), {scene, Rand.seed(seed)}, fn i, {scene, rand} ->
        {u, rand} = Rand.next(rand)
        bx = x0 + u * span

        # Leave the fan's root clear.
        if abs(bx - @fan_x) < 3 do
          {scene, rand}
        else
          {[h, l, k], rand} = Rand.take(rand, 3)
          h = 2 + h * 3.5
          branch(scene, i, bx, top_at.(bx), h, (l - 0.5) * 0.5, if(k < 0.5, do: 1, else: 3), rand)
        end
      end)

    scene
  end

  defp branch(scene, i, bx, base, h, lean, kind, rand) do
    {cr0, cg0, cb0} = elem(@coral, kind)

    scene =
      Stream.iterate(0, &(&1 + 0.5))
      |> Stream.take_while(&(&1 < h))
      |> Enum.reduce(scene, fn s, scene ->
        bent =
          if s > h * 0.55, do: if(rem(i, 2) == 1, do: 1, else: -1) * (s - h * 0.55) * 0.6, else: 0

        x = round_js(bx + lean * s + bent)
        r = round_js(base - s)

        # Writes past the last row fall off the typed arrays.
        if x < 0 or x >= @w or r < 0 or r >= @h do
          scene
        else
          sh = 0.4 + 0.6 * (s / h)

          Map.put(
            scene,
            r * @w + x,
            {@reef, f32(cr0 * sh), f32(cg0 * sh), f32(cb0 * sh), f32(0.06), f32(x * 0.5),
             f32(r * 0.9), f32(0.4)}
          )
        end
      end)

    {scene, rand}
  end

  # --- the moving things, laid out once --------------------------------------
  defp movers do
    rand = Rand.seed(1234)

    {fish, rand} =
      Enum.map_reduce(1..150, rand, fn _, rand ->
        {a, rand} = gauss(rand)
        {b, rand} = gauss(rand)
        {[ph, sp], rand} = Rand.take(rand, 2)
        {{a * 10, b * 3.8, ph * 6.28, 0.8 + sp * 0.6}, rand}
      end)

    {bubbles, rand} =
      for {x0, y0, n} <- @streams, _ <- 1..n, reduce: {[], rand} do
        {bubbles, rand} ->
          {[ph, sp, w], rand} = Rand.take(rand, 3)
          {[{x0, y0, ph, 4 + sp * 3, w * 6.28} | bubbles], rand}
      end

    {snow, _} =
      Enum.map_reduce(1..90, rand, fn _, rand ->
        {[x, y, sp, ph, b], rand} = Rand.take(rand, 5)
        {{x * @w, y * @h, 0.3 + sp * 0.7, ph * 6.28, 0.12 + b * 0.22}, rand}
      end)

    {fish, Enum.reverse(bubbles), snow}
  end

  defp gauss(rand) do
    {[a, b, c, d], rand} = Rand.take(rand, 4)
    {(0 + a + b + c + d - 2) * 1.7, rand}
  end

  # --- what each frame starts from --------------------------------------------
  # The water's colour filters what is behind it: reds go first.
  defp base_static(x, r, {@none, _, _, _, _, _, _, _}, {wr, wg, wb, ray_at}) do
    if r < @surf + 6 do
      dist = @surf + 7 - (r + 0.5)
      {:surface, x, wr, wg, wb, ray_at, (x - 100) / dist * 1.6, (x - 100) / dist * 1.2}
    else
      {:open, wr, wg, wb, ray_at}
    end
  end

  defp base_static(_x, _r, {m, ar, ag, ab, f, cu, cv, cw}, {wr, wg, wb, ray_at}) do
    tint = 1 - f
    # Shallow water: the reef takes plenty of light.
    ex = 1.9

    {:solid, f32(mix(ar * ex * (0.55 + 0.45 * tint), wr, f)),
     f32(mix(ag * ex * (0.85 + 0.15 * tint), wg, f)), f32(mix(ab * ex, wb, f)), ray_at, f, cw, cu,
     cv, m == @sand}
  end

  # The underside of the surface: a rippling ceiling, pressed flat toward
  # the haze.
  defp surface_row(r) when r < @surf + 6 do
    y = r + 0.5
    q = 30 / (@surf + 7 - y)
    h1 = (y - 6) / 3.6
    h2 = (y - 6) / 7
    {q * 6, q * 4.5, :math.pow(smooth(@surf + 6, 0, y), 1.3), h1 * h1, h2 * h2}
  end

  defp surface_row(_r), do: nil

  defp shaft_static(u) do
    q = (u - @ray0) / 60
    0.35 + 0.65 * :math.exp(-(q * q))
  end

  defp kelp_static do
    for {bx, base, len, sz, ph, _haze} <- @kelp do
      # Which way the sun lies.
      side = if bx < 100, do: 1, else: -1

      rows =
        for r <- (base - 1)..max(0, base - len)//-1 do
          s01 = (base - r) / len
          beat = s01 * len * 0.32 + ph
          sb = :math.sin(beat)

          {r, s01 * 4.2, :math.pow(s01, 1.2), s01, side * 2.5 * sz * s01 * s01,
           0.8 + 0.4 * sz * (1 - s01), :math.pow(max(0, sb), 1.2) * sz * 2.3 * (1 - 0.35 * s01),
           :math.pow(max(0, -sb), 1.2) * sz * 2.3 * (1 - 0.35 * s01), :math.exp(-r / 30)}
        end

      {bx, sz, ph, side, rows}
    end
  end

  @impl true
  def frame(state, t, env) do
    # Shafts: a slow pattern across the surface, shimmering as the waves
    # pass, strongest straight under the sun.
    rays =
      List.to_tuple(
        for u <- 0..(@rays - 1) do
          s = :math.pow(smooth(0.5, 0.62, fbm(u * 0.06 + t * 0.025, 3.3, 3)), 1.2)
          shimmer = 0.6 + 0.4 * noise(u * 0.18 - t * 0.7, t * 0.3)
          f32(s * shimmer * elem(state.shafts, u))
        end
      )

    # The sun's blaze wobbles as the swell passes over it.
    hx = @sun_x + 1.6 * :math.sin(t * 0.6) + 0.8 * :math.sin(t * 1.7 + 1)

    blaze =
      List.to_tuple(
        for x <- 0..(@w - 1) do
          q = (x - hx) / 34
          dx = x + 0.5 - hx
          {:math.exp(-(q * q)), -(dx / 8 * (dx / 8)), -(dx / 15 * (dx / 15))}
        end
      )

    fr =
      if state.exact?,
        do:
          {t, rays, blaze, {:fmod, state.caus}, {t * 0.9, t * 0.35, -t * 0.6 + 21, t * 0.5 + 9},
           {t * 1.6, t * 0.8, t * 1.1, t * 0.6}, :exact},
        else:
          {t, rays, blaze, state.caus, {t * 0.9, t * 0.35, -t * 0.6 + 21, t * 0.5 + 9},
           {t * 1.6, t * 0.8, t * 1.1, t * 0.6}, state.ripple}

    base =
      List.to_tuple(
        for {_r, _y, depth_fade, row, cells} <- state.rows,
            do: base_row(cells, depth_fade, row, fr)
      )

    over =
      %{}
      |> school(state.fish, base, t)
      |> kelp(state.kelp, base, rays, state.ray_at, t)
      |> bubbles(state.bubbles, base, t)
      |> snow(state.snow, base, t)
      |> Enum.group_by(fn {k, _} -> div(k, @w) end, fn {k, v} -> {rem(k, @w), v} end)

    acc = {<<>>, <<>>, state.lut, env.color?, if(state.exact?, do: :exact, else: state.power)}

    {text, colors, lut, color?, _} =
      Enum.reduce(0..(@h - 1), acc, fn r, acc ->
        overlays = over |> Map.get(r, []) |> Enum.sort()
        acc = dots_row(Tuple.to_list(elem(base, r)), 0, overlays, r, acc)
        if r < @h - 1, do: newline(acc), else: acc
      end)

    {text, if(color?, do: colors), %{state | lut: lut}}
  end

  defp newline({text, colors, lut, color?, power}),
    do: {<<text::binary, ?\n>>, colors, lut, color?, power}

  defp base_row(cells, depth_fade, row, fr) do
    {_, rays, _, _, _, _, _} = fr
    cells |> base_cells(depth_fade, row, rays, fr, []) |> List.to_tuple()
  end

  defp base_cells([], _depth_fade, _row, _rays, _fr, acc), do: :lists.reverse(acc)

  defp base_cells([cell | cells], depth_fade, row, rays, fr, acc),
    do:
      base_cells(cells, depth_fade, row, rays, fr, [
        base_cell(cell, depth_fade, row, rays, fr) | acc
      ])

  defp base_cell({:open, r, g, b, ray_at}, depth_fade, _row, rays, _fr) do
    ray = elem(rays, ray_at) * depth_fade
    {f32(r + 0.42 * ray), f32(g + 0.86 * ray), f32(b + 0.78 * ray), 0.0}
  end

  defp base_cell({:surface, x, r, g, b, ray_at, u1, u2}, depth_fade, row, rays, fr) do
    ray = elem(rays, ray_at) * depth_fade
    {_t, _rays, blaze, caus, _, {t16, t08, t11, t06}, power} = fr
    a = caus_at(caus, u1 + t16, q6(row) + t08)
    b2 = caus_at(caus, u2 - t11 + 31, q45(row) - t06 + 17)
    m = max(a, b2)
    sky = {r, g, b, ray, row, elem(blaze, x)}

    # Math.pow is slow, so the ripple is first found with power/2, within
    # 1e-14 of pow(m, 1.6). That moves each channel by under 1e-13, so a
    # channel at least 1e-11 from where its Float32Array store would round
    # the other way stores what upstream's does; otherwise the cell is
    # worked out again with :math.pow.
    with true <- power != :exact,
         {r, g, b} = rgb = ceiling(sky, power(m, power)),
         true <- sure?(r) and sure?(g) and sure?(b) do
      stored(rgb)
    else
      _ -> stored(ceiling(sky, :math.pow(m, 1.6)))
    end
  end

  defp base_cell({:solid, r, g, b, ray_at, f, cw, cu, cv, sand?}, depth_fade, _row, rays, fr) do
    ray = elem(rays, ray_at) * depth_fade

    {r, g, b} =
      if cw > 0 do
        {_t, _rays, _blaze, caus, {cx0, cy0, cx1, cy1}, _, _} = fr

        c =
          min(caus_at(caus, cu + cx0, cv + cy0), 1) * 0.6 +
            caus_at(caus, cu * 0.8 + cx1, cv * 0.8 + cy1) * 0.6

        s = cw * c * c * (1 - f) * (0.6 + 0.6 * ray + 0.3 * depth_fade)

        # On the sand the light comes back warm, on the reef cool.
        if sand?,
          do: {r + 0.62 * s, g + 0.66 * s, b + 0.5 * s},
          else: {r + 0.55 * s, g + 0.72 * s, b + 0.62 * s}
      else
        {r, g, b}
      end

    {f32(r + 0.16 * ray * f), f32(g + 0.3 * ray * f), f32(b + 0.28 * ray * f), @floor_solid}
  end

  defp stored({r, g, b}), do: {f32(r), f32(g), f32(b), 0.0}

  defp q6({q6, _, _, _, _}), do: q6
  defp q45({_, q45, _, _, _}), do: q45

  defp ceiling({r, g, b, ray, {_, _, lit, h1, h2}, {near, d8, d15}}, c) do
    # Troughs darken the water under them, crests focus light into lines.
    dim = 1 - lit * 0.7 * (1 - c)
    v = lit * c * (0.1 + 0.42 * near)
    # The sun: a compact blaze through the surface, broken by the ripples.
    hot = :math.exp(d8 - h1) * (1 + 0.3 * c)
    halo = :math.exp(d15 - h2) * 0.3 * (0.6 + 0.6 * c)
    r = r * dim + (0.55 * v + 0.9 * hot + 0.35 * halo)
    g = g * dim + (0.85 * v + 1.0 * hot + 0.6 * halo)
    b = b * dim + (0.8 * v + 0.97 * hot + 0.58 * halo)
    {r + 0.42 * ray, g + 0.86 * ray, b + 0.78 * ray}
  end

  # Whether every value within 1e-11 of v stores the same in a Float32Array.
  defp sure?(v), do: f32(v - @f32_margin) == f32(v + @f32_margin)

  # --- what swims or sways on top ---------------------------------------------
  # Overlaid cells, by index: what a frame has drawn over the base so far.
  defp at(over, base, k) do
    case over do
      %{^k => cell} -> cell
      _ -> elem(elem(base, div(k, @w)), rem(k, @w))
    end
  end

  defp put(over, base, x, r, {pr, pg, pb}, a) when x >= 0 and x < @w and r >= 0 and r < @h do
    k = r * @w + x
    {cr, cg, cb, fl} = at(over, base, k)
    Map.put(over, k, {f32(mix(cr, pr, a)), f32(mix(cg, pg, a)), f32(mix(cb, pb, a)), fl})
  end

  defp put(over, _base, _x, _r, _rgb, _a), do: over

  defp add(over, base, x, r, {pr, pg, pb}) when x >= 0 and x < @w and r >= 0 and r < @h do
    k = r * @w + x
    {cr, cg, cb, fl} = at(over, base, k)
    Map.put(over, k, {f32(cr + pr), f32(cg + pg), f32(cb + pb), fl})
  end

  defp add(over, _base, _x, _r, _rgb), do: over

  # The school: one body turning along a slow loop, each fish a beat behind.
  defp school(over, fish, base, t) do
    Enum.reduce(fish, over, fn {fa, fb, ph, sp}, over ->
      s = t - fa * 0.08
      vx = 24 * 0.11 * :math.cos(0.11 * s + 0.4)
      vy = 8 * 0.17 * :math.cos(0.17 * s + 2.2)
      th = :math.atan2(vy, vx)
      ct = :math.cos(th)
      st = :math.sin(th)
      wob = :math.sin(t * 1.3 * sp + ph)
      px = 95 + 24 * :math.sin(0.11 * s + 0.4) + fa * ct - fb * st + wob * 0.6
      py = 44 + 8 * :math.sin(0.17 * s + 2.2) + fa * st + fb * ct + :math.cos(t * sp + ph) * 0.4
      h = th + 0.15 * wob
      dx = :math.cos(h)
      dy = :math.sin(h)
      # Dark shapes against the light, until a fish turns its silver flank
      # to it.
      flash =
        smooth(0.72, 0.97, abs(:math.sin(th * 1.6 + fa * 0.35 + fb * 0.4 - t * 0.5 + 0.6)))

      rgb = {mix(0.008, 0.85, flash), mix(0.018, 0.97, flash), mix(0.026, 1.0, flash)}

      # The head, then the body behind it.
      Enum.reduce([{0, 1}, {1, 0.85}], over, fn {j, a}, over ->
        put(over, base, round_js(px - dx * j * 0.9), round_js(py - dy * j * 0.9), rgb, a)
      end)
    end)
  end

  # Kelp: dark fronds framing the view, a gold edge only where a shaft hits.
  # Both fronds stand in open water (no haze), so a frond's colour is its own.
  defp kelp(over, kelp, base, rays, ray_at, t) do
    Enum.reduce(kelp, over, fn {bx, sz, ph, side, rows}, over ->
      sway = :math.sin(t * 0.21 + ph)
      t55 = t * 0.55 + ph

      Enum.reduce(rows, over, fn {r, s42, s12, s01, lean, stem, lobe_l, lobe_r, fade}, over ->
        # The swell runs up the frond, so it bends in an S rather than tipping
        # like a stick.
        bend = :math.sin(t55 - s42) * 2.2 * sz * s12 + sway * 1.5 * s01 + lean
        x = bx + bend
        # The frond: a stipe with blades off alternate sides, each blade a
        # lobe that swells and tapers, trailing a little behind the stipe's
        # sway.
        drag = :math.cos(t55 - s42) * 0.8 * sz
        x0 = x - stem - lobe_l + min(0, drag)
        x1 = x + stem + lobe_r + max(0, drag)
        ray = elem(rays, elem(ray_at, r * @w + max(0, min(@w - 1, round_js(x))))) * fade
        lit = smooth(0.3, 0.6, ray)
        xa = round_js(x0)
        xb = round_js(x1)

        Enum.reduce(max(xa, 0)..min(xb, @w - 1)//1, over, fn xx, over ->
          # Backlit: dark through the middle, the edges glowing, the
          # sun-facing edge most of all and gold where a shaft catches it.
          sun? = if side > 0, do: xx == xb, else: xx == xa
          rim? = xx == xa or xx == xb
          blade = if abs(xx - x) > stem, do: 1, else: 0
          # The stipe is black, the blades let a little olive light through.
          through =
            blade * 0.12 * smooth(0, 1, abs(xx - x) - stem) * (0.5 + 0.5 * hash(xx * 7, r * 3))

          g =
            0.02 + through + if(rim?, do: 0.16, else: 0) +
              if(sun?, do: 0.34 + 0.66 * lit * (0.4 + 0.6 * blade), else: 0)

          over = put(over, base, xx, r, {0.62 * g, 0.58 * g, 0.18 * g}, 1)
          {cr, cg, cb, _} = Map.fetch!(over, r * @w + xx)
          Map.put(over, r * @w + xx, {cr, cg, cb, @floor_solid})
        end)
      end)
    end)
  end

  # Bubbles: wobbling up to the surface, growing as they rise.
  defp bubbles(over, bubbles, base, t) do
    Enum.reduce(bubbles, over, fn {x0, y0, ph, sp, w}, over ->
      span = y0 - @surf
      p = JSMath.mod(t * sp / span + ph, 1)
      y = y0 - p * span
      x = x0 + :math.sin(y * 0.35 + w) * 1.2 + p * 3
      v = 0.55 + 0.45 * p
      add(over, base, round_js(x), round_js(y), {0.7 * v, 0.95 * v, 1.0 * v})
    end)
  end

  # Specks drifting in the water.
  defp snow(over, snow, base, t) do
    Enum.reduce(snow, over, fn {sx, sy, sp, ph, b}, over ->
      x = JSMath.mod(JSMath.mod(sx + t * sp + 2 * :math.sin(t * 0.3 + ph), @w) + @w, @w)
      y = JSMath.mod(JSMath.mod(sy + t * sp * 0.4, @h) + @h, @h)
      add(over, base, floor(x), floor(y), {b * 0.7, b * 0.9, b})
    end)
  end

  defp dots_row([], _x, _overlays, _r, acc), do: acc

  defp dots_row([cell | cells], x, overlays, r, acc) do
    {{cr, cg, cb, fl}, overlays} =
      case overlays do
        [{^x, over} | rest] -> {over, rest}
        _ -> {cell, overlays}
      end

    acc = dot(cr, cg, cb, fl, elem(@bayer, band(r, 3) * 4 + band(x, 3)), acc)
    dots_row(cells, x + 1, overlays, r, acc)
  end

  # Dot size from brightness, dithered. Then the colour makes up what the dot
  # size could not: a small dot is drawn brighter and a large one dimmer, so
  # a gradient stays smooth across the dither's steps.
  #
  # Math.pow is slow, so the level is first found with power/2, within
  # 1e-13 of pow(peak, 0.85). Every decision the level feeds (the dot's
  # rounding, the colour's step in the cache, a cache miss) is then checked:
  # when one sits within 1e-8 of its threshold, or the colour is not cached
  # yet, the cell is worked out again with :math.pow, so the result is
  # always upstream's.
  defp dot(cr, cg, cb, fl, bayer, {_, _, _, _, :exact} = acc),
    do: exact_dot(cr, cg, cb, fl, bayer, cr |> max(cg) |> max(cb) |> max(1.0e-4), acc)

  defp dot(cr, cg, cb, fl, bayer, {text, colors, lut, color?, power} = acc) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(fl + (1 - fl) * power(peak, power) * 0.95)
    v = level * 3 + bayer
    whole = floor(v)
    f = v - whole

    if abs(f - 0.5) < @margin do
      exact_dot(cr, cg, cb, fl, bayer, peak, acc)
    else
      # Math.round, away from the half.
      step = if f < 0.5, do: whole, else: whole + 1
      step = max(0, min(3, step))
      text = <<text::binary, elem(@dots, step)::binary>>

      case color? && cached(lut, tint(cr, cg, cb, level, step, peak)) do
        false -> {text, colors, lut, false, power}
        nil -> exact_color(cr, cg, cb, fl, bayer, peak, {text, colors, lut, true, power})
        index -> {text, <<colors::binary, index>>, lut, true, power}
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

  defp exact_level(fl, peak), do: clamp(fl + (1 - fl) * :math.pow(peak, @gamma) * 0.95)

  defp exact_dot(cr, cg, cb, fl, bayer, peak, {text, colors, lut, color?, power}) do
    level = exact_level(fl, peak)
    step = max(0, min(3, round_js(level * 3 + bayer)))
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
  defp exact_color(cr, cg, cb, fl, bayer, peak, {text, colors, lut, true, power}) do
    level = exact_level(fl, peak)
    step = max(0, min(3, round_js(level * 3 + bayer)))
    {r, g, b} = tint(cr, cg, cb, level, step, peak)
    {index, lut} = Palette.nearest(lut, r, g, b)
    {text, <<colors::binary, index>>, lut, true, power}
  end
end
