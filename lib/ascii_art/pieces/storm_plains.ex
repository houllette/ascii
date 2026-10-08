defmodule AsciiArt.Pieces.StormPlains do
  @moduledoc """
  An anvil thunderhead at dusk flickering over a wheat field.

  An anvil thunderhead at dusk over open wheat country. The sun has just set
  behind the farmhouse, so the storm's top and western flank still catch its
  light while the base sinks into slate shadow. Lightning flickers inside the
  cloud, now and then a bolt reaches the ground, rain curtains drift under
  the base and the wheat moves in gusts.

  The cloud is built as a height field (heaped domes, a flat anvil, pouches
  hanging under it) and lit from its surface normals. Every cell is shaded
  in colour, then drawn as a halftone: dot size from brightness with an
  ordered dither, colour from the palette entry nearest its hue.

  Ported from `src/pieces/storm-plains.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Hash, Palette, Scene}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "storm plains",
    category: :scenes,
    note: "an anvil thunderhead at dusk flickering over a wheat field",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#0b0912",
    palette: [
      # night violets, zenith to dusk
      "#0f0c20",
      "#141029",
      "#1c1638",
      "#261c4a",
      "#32235a",
      "#40306c",
      "#53407e",
      "#6a5590",
      "#8670a6",
      # dusty mauve, the shaded flank
      "#7a6288",
      "#9a7890",
      "#b98e94",
      # peach and gold, the sunlit tops
      "#e6a890",
      "#f2bca8",
      "#f7d6a8",
      "#fbe8c6",
      # amber afterglow
      "#f8b070",
      "#e88a4c",
      "#c8643a",
      "#9a4630",
      "#6a3226",
      # wheat, gold to umber
      "#f0c868",
      "#d8a447",
      "#b7843a",
      "#8c6230",
      "#5e4226",
      "#3a2a1c",
      "#261c14",
      # rain and slate
      "#181a2c",
      "#2a3048",
      "#3a4260",
      "#4f5878",
      "#6a7392",
      "#8890ae",
      "#a2aabd",
      "#5d5878",
      "#7c7598",
      # lightning
      "#a6a2c8",
      "#d6d2fa",
      "#f4f2ff",
      # lamplight
      "#ffe08a",
      "#ffb84a"
    ]
  }

  @w 200
  @h 100
  # The horizon.
  @hz 64
  # Just below the horizon, behind the farmhouse.
  @sun_x 30
  @sun_y 70
  # The storm's flat base.
  @base 45
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()

  @sky 0
  @plain 1
  @field 2
  @road 3
  @house 4
  @roof 5
  @pane 6
  @tree 7
  @pump 8
  @belt 9

  # The height field's grid: two cells of margin either side.
  @sx @w + 4
  @sy @base + 8
  # Toward the light: west, a touch high, out of the page.
  @lx -0.72
  @ly -0.3
  @lz 0.62
  # The farmhouse's walls run from x 40 to 54, its eaves at row 58.
  @hx0 40
  @hx1 54
  @hw0 58
  @pump_x 66
  # The wheat's vanishing column, and the widths of the wrapping fields.
  @vx 57
  @tw 512
  @gw 512
  @cw 400
  @rw 256
  # Lightning: a flash schedule, and flickers between.
  @period 3.1
  @fl 1.6
  # The palette entry for the wheat stalks in front of us.
  @stalk 24

  @impl true
  def meta, do: @meta

  @compile {:inline, clamp: 1, smooth: 3, mix: 3, fround: 1}
  defp clamp(v) when v < 0, do: 0
  defp clamp(v) when v > 1, do: 1
  defp clamp(v), do: v

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  defp fround(x), do: JSMath.fround(x)

  defp noise(x, y, period), do: Scene.noise(x, y, period)
  defp fbm(x, y, octaves, period), do: Scene.fbm(x, y, octaves, period)
  defp hash(x, y), do: Hash.scene(x, y)

  defp dome(dx, dy, r) do
    q = 1 - dx * dx - dy * dy
    if q > 0, do: r * :math.sqrt(q), else: 0
  end

  # Distance from (px, py) to the segment a-b.
  defp seg_dist(px, py, ax, ay, bx, by) do
    dx = bx - ax
    dy = by - ay
    len = dx * dx + dy * dy
    k = clamp(((px - ax) * dx + (py - ay) * dy) / if(len == 0, do: 1, else: len))
    ex = px - ax - dx * k
    ey = py - ay - dy * k
    :math.sqrt(ex * ex + ey * ey)
  end

  # --- the thunderhead, as a height field ------------------------------------

  defp tower_c(y), do: 138 + (@base - y) * 0.14
  defp tower_hw(y), do: 23 - (@base - y) * 0.08
  defp anvil_top(x), do: 7.5 + 2.5 * smooth(150, 210, x) + 3 * smooth(112, 58, x)
  defp anvil_bot(x), do: 21 - 9 * smooth(124, 62, x) - 7 * smooth(152, 210, x)

  defp rnd(seed), do: {hash(seed, 911), seed + 1}

  # The towers are heaps of puffs: {x, y, radius, bulge toward us, flat}.
  # Each puff is a dome in the height field, so it gets its own lit side and
  # shadow. (The list comes out last first; only the highest dome over a
  # cell counts, so its order does not matter.)
  defp puffs do
    {puffs, seed} = towers(@base - 4.5, [], 1)
    # The overshooting top, bulging out of the anvil.
    puffs = [{141, 8.5, 9, 2, 0}, {133, 9.5, 6, 1, 0}, {149, 10, 6, 1, 0} | puffs]

    # The flanking line: younger towers stepping down to the west.
    {puffs, seed} =
      Enum.reduce([{104, 27, 9}, {89, 34, 6.5}, {77, 40.5, 3.8}], {puffs, seed}, fn
        {cx, top, w}, {puffs, seed} ->
          {puffs, seed} = flanker(cx, top, w, @base - w * 0.4, puffs, seed)

          {[
             {cx - w * 0.35, top + w * 0.75, w * 0.62, 1, 1},
             {cx + w * 0.3, top + w * 0.6, w * 0.7, 1.5, 1},
             {cx, top + w * 0.45, w * 0.55, 2, 1} | puffs
           ], seed}
      end)

    # One continuous low base under the line, so the towers stand on
    # something.
    low_base(66, puffs, seed)
  end

  defp towers(y, puffs, seed) when y > 14 do
    cx = tower_c(y)
    hw = tower_hw(y)
    n = max(2, JSMath.round(hw * 2 / 11))

    {puffs, seed} =
      Enum.reduce(0..(n - 1), {puffs, seed}, fn i, {puffs, seed} ->
        u = (i + 0.5) / n * 2 - 1
        {a, seed} = rnd(seed)
        rr = 7 + a * 4
        {b, seed} = rnd(seed)
        {c, seed} = rnd(seed)

        {[
           {cx + u * (hw - rr * 0.55) + (b - 0.5) * 3, y + (c - 0.5) * 2, rr,
            4 * :math.sqrt(1 - u * u * 0.85), 1}
           | puffs
         ], seed}
      end)

    towers(y - 4.4, puffs, seed)
  end

  defp towers(_y, puffs, seed), do: {puffs, seed}

  defp flanker(cx, top, w, y, puffs, seed) do
    if y > top + w * 0.6 do
      {a, seed} = rnd(seed)
      {b, seed} = rnd(seed)
      puffs = [{cx + (a - 0.5) * w * 0.6, y, w * (0.75 + b * 0.2), 1, 1} | puffs]
      flanker(cx, top, w, y - w * 0.75, puffs, seed)
    else
      {puffs, seed}
    end
  end

  defp low_base(x, puffs, seed) when x < 126 do
    {a, seed} = rnd(seed)
    {b, seed} = rnd(seed)
    puffs = [{x, @base - 1.8 - a * 1.2, 3 + b * 1.6 + 1.6 * smooth(70, 110, x), 0.4, 1} | puffs]
    {c, seed} = rnd(seed)
    low_base(x + (3.2 + c * 1.6), puffs, seed)
  end

  defp low_base(_x, puffs, _seed), do: puffs

  # The height, how much of it is anvil, and the anvil's sunlit top edge, on
  # the grid: three tuples of rows.
  defp height_field(puffs) do
    rows =
      for r <- 0..(@sy - 1) do
        row = for i <- 0..(@sx - 1), do: height(i - 2 + 0.5, r + 0.5, puffs)

        {row |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
         row |> Enum.map(&elem(&1, 1)) |> List.to_tuple(),
         row |> Enum.map(&elem(&1, 2)) |> List.to_tuple()}
      end

    {rows |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
     rows |> Enum.map(&elem(&1, 1)) |> List.to_tuple(),
     rows |> Enum.map(&elem(&1, 2)) |> List.to_tuple()}
  end

  defp height(x, y, puffs) do
    # The towers, cut flat along the base.
    cut = smooth(@base + 1, @base - 1.5, y + 1.2 * (noise(x * 0.15, 3.3, 0) - 0.5))

    tower =
      Enum.reduce(puffs, 0, fn {px, py, pr, pz, flat}, tower ->
        dx = (x - px) / pr
        dy = (y - py) / pr

        if dx * dx + dy * dy >= 1 do
          tower
        else
          v =
            (pr * 0.6 + pz) * :math.sqrt(1 - dx * dx - dy * dy) * if(flat != 0, do: cut, else: 1)

          if v > tower, do: v, else: tower
        end
      end)

    # The anvil: flat on top, a lens in section, combed by the wind.
    fib = fbm(x * 0.035, y * 0.2, 3, 0) - 0.5
    top = anvil_top(x) + 2.2 * fib
    bot = anvil_bot(x) - 1.5 * fib - 3 * (fbm(x * 0.2, 7, 2, 0) - 0.5)
    mid = (top + bot) / 2
    half = max(0.5, (bot - top) / 2)
    anvil = dome(0, (y - mid) / half, min(5, half * 0.9)) * smooth(58, 72, x + 6 * fib)
    on_top = if anvil > 0, do: smooth(top + 3.2, top + 0.6, y), else: 0
    anvil = mammatus(x, y, bot, anvil)
    h = max(tower, anvil)
    a = if anvil > tower, do: smooth(0, 2, anvil - tower), else: 0
    # Small billows on the towers; long streaks on the anvil, combed at a
    # slight slant so they do not line up with the rows.
    billow = fbm(x * 0.22, y * 0.24, 3, 0) - 0.5
    sy = y * 0.18 + 0.9 * (noise(x * 0.04, 5.5, 0) - 0.5) + x * 0.012
    streaky = fbm(x * 0.03 + 0.6 * noise(x * 0.08, y * 0.1, 0), sy, 3, 0) - 0.5
    h = h + min(1, h / 2.5) * mix(3 * billow, 2.2 * streaky, a)
    {fround(max(0, h)), fround(a), fround(on_top * a)}
  end

  # Pouches of mammatus hanging under its western half.
  defp mammatus(x, y, bot, anvil) when x > 66 and x < 128 and y > bot - 2 and y < bot + 5 do
    row = floor((x - 66) / 5.2)
    off = row * 5.2 + 66 + 2.6 + (hash(row, 3) - 0.5) * 1.2
    py = bot + 0.6 + hash(row, 4) * 1.2

    max(
      anvil,
      dome((x - off) / 2.7, (y - py) / 2.3, 2.2) * smooth(64, 76, x) * smooth(130, 116, x)
    )
  end

  defp mammatus(_x, _y, _bot, anvil), do: anvil

  # --- the static colour of every cell: sky, storm, land ---------------------

  defp glow_sun(x, y) do
    dx = x - @sun_x
    dy = y - @sun_y
    a = dx / 48
    b = dy / 10
    c = dx / 95
    d = dy / 20
    :math.exp(-(a * a) - b * b) * 0.9 + :math.exp(-(c * c) - d * d) * 0.26
  end

  # The farmhouse, its tree and a windpump, standing on the horizon.
  defp ground(x), do: @hz + 3 - 1.2 * smooth(20, 70, x) * smooth(110, 70, x)

  # The shelf: a flat dark lip of cloud along the storm's leading edge.
  defp shelf_top(x), do: @base - 2.4 + 1.2 * (noise(x * 0.2, 8.1, 0) - 0.5)

  defp shelf_bot(x),
    do:
      @base + 2.4 + 1.8 * (fbm(x * 0.12, 8.7, 2, 0) - 0.5) - 2 * smooth(184, 199, x) -
        2 * smooth(114, 104, x)

  defp shelf_on(x), do: smooth(103, 112, x) * smooth(199, 190, x)

  # The road: from the yard to the bottom edge, a leading line.
  defp road_c(p), do: 57 + 62 * :math.pow(p, 1.25)
  defp road_w(p), do: 0.6 + 12 * p

  # Each cell as {material, r, g, b, cloud, dark, floor}, the floats as the
  # Float32Arrays hold them.
  defp statics(field) do
    hb = ground(47)

    for r <- 0..(@h - 1), x <- 0..(@w - 1), into: %{} do
      y = r + 0.5

      {m, cr, cg, cb, cloud, dark, floor} =
        if y < ground(x), do: sky_cell(x, r, y, field), else: land_cell(x, y)

      m = m |> scenery(x, y, hb) |> road(x, r)
      {{r, x}, {m, cr, cg, cb, cloud, dark, floor}}
    end
  end

  # Land: the afterglow caught only in the far rows near the sun.
  defp land_cell(x, y) do
    g = glow_sun(x, @hz + 1) * :math.exp(-(y - @hz) / 3.2)
    m = if y < @hz + 4, do: @plain, else: @field

    {m, fround(0.06 + 0.55 * g), fround(0.045 + 0.3 * g), fround(0.08 + 0.1 * g), 0, 0,
     fround(0.06)}
  end

  # Sky: indigo overhead, dusky rose lower down, amber where the sun went.
  defp sky_cell(x, r, y, field) do
    v = y / @hz
    g = glow_sun(x, y)
    # The storm side is cooler and darker.
    east = smooth(60, 190, x)
    v2 = :math.pow(v, 2.2)
    veil = 0.9 + 0.2 * fbm(x * 0.05, y * 0.09, 3, 0)
    cr = (0.045 + 0.2 * v2 * (1 - 0.6 * east)) * veil + 1.0 * g
    cg = (0.045 + 0.09 * v2 * (1 - 0.5 * east)) * veil + 0.56 * g
    cb = (0.16 + 0.13 * v2 * (1 - 0.35 * east)) * veil + 0.22 * g
    # The last light along the horizon, gone where the storm stands.
    be = smooth(45, 118, x)
    band = :math.exp(-(@hz + 2 - y) / 11) * (1 - 0.85 * be) * (1 - 0.6 * g)
    cr = cr + band * mix(0.5, 0.34, be)
    cg = cg + band * mix(0.26, 0.21, be)
    cb = cb + band * mix(0.26, 0.3, be)
    # Under the storm the air itself goes dark slate, with only a thread of
    # light left along the ground behind the rain: black under the base,
    # opening to a dim violet glow at the ground, the clear sky far beyond
    # the storm, for the rain to hang against.
    under =
      smooth(98, 128, x + 8 * (noise(y * 0.15, 4.4, 0) - 0.5)) *
        smooth(@base - 14, @base - 1, y)

    slot =
      :math.pow(smooth(@base + 1.5, @hz - 6, y), 0.5) * (0.85 + 0.3 * noise(x * 0.06, 6.6, 0))

    cr = mix(cr, mix(0.035, 0.38, slot) * veil, under * 0.92)
    cg = mix(cg, mix(0.032, 0.3, slot) * veil, under * 0.92)
    cb = mix(cb, mix(0.075, 0.56, slot) * veil, under * 0.92)
    dark_sky = fround(under)

    {cr, cg, cb, cloud, dark} =
      if r < @sy - 1, do: storm(x, r, y, field, cr, cg, cb), else: {cr, cg, cb, 0, 0}

    {cr, cg, cb, cloud, dark} = shelf(x, y, cr, cg, cb, cloud, dark)

    {@sky, fround(cr), fround(cg), fround(cb), cloud, dark,
     fround(0.06 - 0.06 * max(dark_sky, dark))}
  end

  # The storm, lit from its surface normals.
  defp storm(x, r, y, {sh, anv, lip}, cr, cg, cb) do
    i = x + 2
    row = elem(sh, r)
    h = elem(row, i)
    c = smooth(0.15, 1.6, h)

    if c > 0 do
      up = if r > 0, do: elem(elem(sh, r - 1), i), else: 0
      dn = elem(elem(sh, r + 1), i)
      gx = (elem(row, i + 1) - elem(row, i - 1)) / 2
      gy = (dn - up) / 2
      nl = :math.sqrt(gx * gx + gy * gy + 1)
      nx = -gx / nl
      ny = -gy / nl
      nz = 1 / nl
      an = elem(elem(anv, r), i)
      lam = :math.pow(clamp(nx * @lx + ny * @ly + nz * @lz), 1.5)
      {kr, kg, kb, base} = storm_light(x, y, h, ny, an, lam, elem(elem(lip, r), i))
      {mix(cr, kr, c), mix(cg, kg, c), mix(cb, kb, c), fround(c), fround(base * c)}
    else
      {cr, cg, cb, 0, 0}
    end
  end

  defp storm_light(x, y, h, ny, an, lam, lip) do
    # Earth's shadow climbing the tower: the tops still lit, the lower bulk
    # already in dusk.
    vis = 1 - 0.4 * smooth(22, @base - 4, y + 5 * (noise(x * 0.12, 2.2, 0) - 0.5))
    a = smooth(8, @base, y)
    q = (x - @sun_x) / 110
    near = :math.exp(-(q * q))
    # The younger towers to the west.
    flank = smooth(122, 108, x) * (1 - an)
    # Sunlight: cream-gold up high, peach lower down.
    sr = 1.0
    sg = mix(0.84, 0.58, a)
    sb = mix(0.58, 0.45, a)
    # The tower's own bulk shades its eastern side, along a ragged edge.
    ej = 8 * (fbm(y * 0.14 + x * 0.02, 21.3, 3, 0) - 0.5)

    lee =
      1 -
        0.65 * smooth(tower_c(y) - 14 + ej, tower_c(y) + tower_hw(y) + 16 + ej, x) * (1 - an) *
          smooth(anvil_bot(x) - 3, anvil_bot(x) + 9, y + 5 * (noise(x * 0.15, 21, 0) - 0.5)) *
          if(y < @base, do: 1, else: 0)

    sun = lam * vis * lee * (0.95 + 0.4 * near) * (1 - 0.3 * flank) * (1 - 0.2 * an)
    # Skylight from above, violet; afterglow bounced up from the west.
    sky = 0.55 + 0.45 * max(0, -ny)
    bounce = max(0, ny) * (0.2 + 0.45 * near) * (1 - 0.6 * flank) * (1 - 0.5 * an)
    occ = 1 - 0.35 * smooth(4, 22, h) * (1 - lam)
    kr = (0.27 * sky + sr * sun + 0.36 * bounce) * occ
    kg = (0.2 * sky + sg * sun + 0.16 * bounce) * occ
    kb = (0.45 * sky + sb * sun + 0.16 * bounce) * occ
    # The anvil's underside sinks into mauve shadow; its top edge catches
    # the last direct light, cream toward the west.
    below = clamp(ny * 2.2) * an
    kr = kr * (1 - 0.42 * below)
    kg = kg * (1 - 0.46 * below)
    kb = kb * (1 - 0.3 * below)
    rim = lip * smooth(196, 120, x) * (0.6 + 0.4 * lam)
    kr = mix(kr, 0.98, rim * 0.75)
    kg = mix(kg, 0.86, rim * 0.75)
    kb = mix(kb, 0.64, rim * 0.75)
    # The flankers' lower halves turn violet-grey.
    low = clamp(ny * 1.6 + 0.2) * flank
    kr = mix(kr, 0.14, low * 0.65)
    kg = mix(kg, 0.11, low * 0.65)
    kb = mix(kb, 0.24, low * 0.65)
    # The base: dark slate where the rain hangs.
    base = smooth(@base - 4.5, @base - 0.5, y) * (1 - an) * (1 - 0.3 * near)
    {mix(kr, 0.03, base * 0.9), mix(kg, 0.026, base * 0.9), mix(kb, 0.06, base * 0.9), base}
  end

  # The shelf, hung along the base, a touch lighter on its leading lip.
  defp shelf(x, y, cr, cg, cb, cloud, dark) do
    on = shelf_on(x)

    with true <- on > 0 and y > @base - 5 and y < @base + 5,
         st = shelf_top(x),
         sbt = shelf_bot(x),
         s = smooth(st - 1, st + 0.6, y) * smooth(sbt + 0.6, sbt - 0.8, y) * on,
         true <- s > 0 do
      n = fbm(x * 0.15, y * 0.5, 2, 0)
      # Striations along its face, and a faint lip of light underneath.
      lit =
        0.55 + 0.9 * n * (0.7 + 0.6 * noise(x * 0.05, y * 1.3, 0)) +
          0.9 * smooth(sbt - 1.6, sbt - 0.2, y)

      {mix(cr, 0.06 * lit, s), mix(cg, 0.056 * lit, s), mix(cb, 0.12 * lit, s),
       fround(max(cloud, s)), fround(max(dark, s))}
    else
      false -> {cr, cg, cb, cloud, dark}
    end
  end

  # The shelterbelt, the cottonwood, the farmhouse and the windpump, each
  # painted over what is there.
  defp scenery(m, x, y, hb) do
    # A shelterbelt of trees on the far horizon, half lost in the rain.
    belt =
      @hz + 2 -
        (1.5 + 2.2 * fbm(x * 0.3, 2, 2, 0)) * smooth(140, 150, x) * smooth(196, 186, x)

    belt2 = @hz + 2 - (1 + 1.8 * fbm(x * 0.35, 9, 2, 0)) * smooth(0, 4, x) * smooth(18, 10, x)
    m = if y >= min(belt, belt2) and y < @hz + 3, do: @belt, else: m

    # The cottonwood by the house.
    tx = (x + 0.5 - 31) / 8.5
    ty = (y - (hb - 10)) / 7
    crown = tx * tx + ty * ty < 1 + 0.35 * (fbm(x * 0.4, y * 0.4, 2, 0) - 0.5)

    m =
      if crown or (abs(x + 0.5 - 31.5) < 1 and y > hb - 6 and y < hb + 1), do: @tree, else: m

    m |> farmhouse(x, y, hb) |> windpump(x, y, hb)
  end

  # Two storeys, a gable roof, a chimney, a porch.
  defp farmhouse(m, x, y, hb) do
    m
    |> paint_if(x >= @hx0 and x <= @hx1 and y >= @hw0 and y < hb + 1, @house)
    |> paint_if(gable?(x, y), @roof)
    |> paint_if(x >= 50 and x <= 51 and y >= @hw0 - 8 and y < @hw0 - 3, @roof)
    |> paint_if(x >= 36 and x < @hx0 and y >= hb - 4 and y < hb - 3, @roof)
    |> paint_if(x == 36 and y >= hb - 3 and y < hb, @house)
    |> paint_if(x >= 49 and x <= 51 and y >= @hw0 + 2 and y < @hw0 + 5, @pane)
    |> paint_if(x >= 43 and x <= 44 and y >= @hw0 + 2 and y < @hw0 + 4, @pane)
  end

  defp gable?(x, y),
    do: y >= @hw0 - 7 and y < @hw0 and abs(x + 0.5 - 47.5) <= 8.6 - (@hw0 - y) * 1.15

  defp paint_if(_m, true, n), do: n
  defp paint_if(m, false, _n), do: m

  # A tapering lattice tower.
  defp windpump(m, x, y, hb) do
    py = y - (hb - 15)

    if py > 2 and y < hb + 0.5 do
      half = 0.4 + py * 0.11
      dx = x + 0.5 - @pump_x
      m = if abs(abs(dx) - half) < 0.55, do: @pump, else: m
      if abs(dx) < half and rem(trunc(py), 4) == 0, do: @pump, else: m
    else
      m
    end
  end

  defp road(@field, x, r) when r >= @hz + 3 do
    p = (r + 0.5 - @hz) / (@h - @hz)

    if abs(x + 0.5 - road_c(p)) < road_w(p) + 0.6 * (noise(x * 0.3, r * 0.3, 0) - 0.5),
      do: @road,
      else: @field
  end

  defp road(m, _x, _r), do: m

  # --- the moving parts, built once ------------------------------------------

  # Wheat: stalks in perspective, their columns converging on the farmhouse,
  # tall strokes up close and a fine grain toward the horizon. By row from
  # the horizon down.
  defp wheat do
    List.to_tuple(
      for r <- @hz..(@h - 1) do
        p = (r + 0.5 - @hz) / (@h - @hz)

        List.to_tuple(
          for u <- 0..(@tw - 1), do: fround(fbm(u * 0.55, r * (0.5 - 0.42 * p), 3, @tw * 0.55))
        )
      end
    )
  end

  # Gusts: soft patches of bent, brighter wheat rolling across the field.
  defp gusts do
    List.to_tuple(
      for r <- @hz..(@h - 1) do
        List.to_tuple(
          for u <- 0..(@gw - 1),
              do: fround(smooth(0.4, 0.7, fbm(u * 0.025, r * 0.16, 3, @gw * 0.025)))
        )
      end
    )
  end

  # Thin glowing streaks of altostratus in the clear western sky (rows 41
  # to 60; nothing elsewhere).
  defp streaks do
    List.to_tuple(
      for r <- 0..(@hz - 1) do
        fade = smooth(40, 46, r) * smooth(@hz - 3, 52, r)

        if fade == 0 do
          nil
        else
          List.to_tuple(
            for u <- 0..(@cw - 1) do
              n = fbm(u * 0.02, r * 0.2, 4, @cw * 0.02)
              fround(smooth(0.64, 0.8, n) * smooth(40, 46, r) * smooth(@hz - 3, 52, r))
            end
          )
        end
      end
    )
  end

  # Wheat ears right in front of us, bowing with the wind: {x, stalk height,
  # phase, foot below the frame, head length}.
  defp ears(x) when x < @w do
    ear =
      {x, 8 + hash(x * 3, 61) * 12, hash(x * 7, 62) * 6.28, hash(x * 5, 63) * 6,
       5 + if(hash(x, 64) > 0.5, do: 1, else: 0)}

    [ear | ears(x + (5 + hash(x, 60) * 4))]
  end

  defp ears(_x), do: []

  # Lightning: four bolts, each a random walk with a branch or two, and how
  # far every cell around it lies from it (99 where none is near).
  defp bolts do
    List.to_tuple(
      for i <- 0..3 do
        segs = walk(i, 122 + hash(i, 40) * 34, @base - 4, 40, (hash(i, 44) - 0.5) * 0.8, 0)
        [{x0, _, _, _, _} | _] = segs

        field =
          List.to_tuple(
            for r <- 0..(@h - 1) do
              if r >= 25 and r < @hz + 4 do
                List.to_tuple(for x <- 0..(@w - 1), do: bolt_distance(x, r, segs))
              end
            end
          )

        {x0, field}
      end
    )
  end

  defp walk(i, x, y, len, lean, depth), do: walk(i, x, y, len, lean, depth, 0)

  defp walk(i, x, y, len, lean, depth, s) when s < len and y < @hz + 2 do
    nx = x + (hash(i * 97 + s, depth * 13 + 41) - 0.5) * 3.2 + lean
    ny = y + 0.9 + hash(i * 31 + s, depth + 42) * 1.3

    branch =
      if depth == 0 and hash(i * 7 + s, 43) > 0.84,
        do: walk(i, nx, ny, 3 + hash(s, i) * 5, (hash(s, i + 9) - 0.5) * 2.4, 1),
        else: []

    [{x, y, nx, ny, depth} | branch] ++ walk(i, nx, ny, len, lean, depth, s + 1)
  end

  defp walk(_i, _x, _y, _len, _lean, _depth, _s), do: []

  defp bolt_distance(x, _r, _segs) when x < 80, do: 99

  defp bolt_distance(x, r, segs) do
    segs
    |> Enum.reduce(99, fn {ax, ay, bx, by, dep}, m ->
      if abs(x - ax) > 14 and abs(x - bx) > 14 do
        m
      else
        d = seg_dist(x + 0.5, r + 0.5, ax, ay, bx, by) + dep * 0.5
        if d < m, do: d, else: m
      end
    end)
    |> fround()
  end

  # --- init ------------------------------------------------------------------

  @impl true
  def init(_options) do
    statics = statics(height_field(puffs()))
    hb = ground(47)
    pump_y = hb - 15

    # Stars in the darkest part of the sky.
    stars =
      for r <- 0..27,
          x <- 0..99,
          hash(x, r * 5 + 3) > 0.986,
          elem(statics[{r, x}], 4) < 0.05,
          into: %{},
          do:
            {{r, x},
             {hash(x, r) * 6.28, 1 + hash(r, x) * 2.5, 0.85 * (1 - r / 28) * (1 - x / 130)}}

    # Rain: one envelope of shafts that drifts, and falling streaks in it.
    shafts =
      List.to_tuple(
        for u <- 0..(@rw - 1), do: fround(smooth(0.47, 0.57, fbm(u * 0.09375, 0.5, 2, 24)))
      )

    columns =
      List.to_tuple(
        for x <- 0..(@w - 1) do
          {fround(hash(x, 77) * 40), fround(22 + hash(x, 78) * 14), fround(shelf_bot(x) - 1.5),
           fround(smooth(106, 118, x) * smooth(198, 186, x))}
        end
      )

    cells =
      List.to_tuple(
        for r <- 0..(@h - 1) do
          List.to_tuple(
            for x <- 0..(@w - 1),
                do: cell(x, r, statics[{r, x}], stars[{r, x}], columns, pump_y)
          )
        end
      )

    %{
      cells: cells,
      rows: List.to_tuple(for r <- 0..(@h - 1), do: row(r)),
      wheat: wheat(),
      gusts: gusts(),
      streaks: streaks(),
      shafts: shafts,
      ears: ears(2),
      bolts: bolts(),
      lut: Palette.nearest_lut(@meta.palette)
    }
  end

  # Per row: the depth into the field, the wheat's contrast there, and the
  # fade into the ground at the bottom.
  defp row(r) do
    y = r + 0.5
    p = (y - @hz) / (@h - @hz)
    {y, p, 0.9 + 1.4 * p, smooth(@h + 10, @h - 8, y)}
  end

  # What a cell keeps: its kind, with what that needs; the parts every kind
  # may get (the dither's jitter, the pane's glow on it, the windpump wheel,
  # what lightning sees there); and its dot when nothing moves.
  defp cell(x, r, {m, cr, cg, cb, cloud, dark, floor}, star, columns, pump_y) do
    y = r + 0.5
    # Per-cell dither jitter, against contour lines.
    jit = fround((hash(x, r + 517) - 0.5) * if(r < @hz, do: 0.16, else: 0.06))
    light = {m == @sky, cloud, dark}
    kind = kind(m, x, r, y, {cr, cg, cb, cloud, floor}, star, columns)
    common = {jit, pane_glow(m, x, y), wheel(x, y, pump_y), light}
    {kind, common, still(kind, x, r, common)}
  end

  # The dot of a cell whose colour does not move, as long as nothing passes
  # over it.
  defp still({:fixed, cr, cg, cb, floor, fade}, x, r, {jit, glow, nil, _light}) do
    {cr, cg, cb} = glow(glow, cr, cg, cb)
    halftone_static(x, r, cr, cg, cb, floor, fade, jit)
  end

  defp still(_kind, _x, _r, _common), do: nil

  defp kind(@sky, x, r, y, {cr, cg, cb, c, floor}, star, columns) do
    # The altostratus, lit gold toward the sun.
    streak =
      if c < 0.98 and r < @hz and r > 40 and r < 61 and x < 105 do
        q = (x - @sun_x) / 80
        {1 - c, smooth(105, 55, x), :math.exp(-(q * q))}
      end

    star =
      case star do
        {ph, sp, a} when c < 0.98 and r < @hz -> {ph, sp, a, 1 - c}
        _ -> nil
      end

    {_, _, top, on} = elem(columns, x)
    # Rain curtains hanging from the shelf to the ground.
    rain =
      if on > 0 and y > top do
        col = rem(floor(x + (y - @base) * 0.42), @w)
        {col_phase, col_speed, _, _} = elem(columns, col)

        {x + (y - @base) * 0.42, on, smooth(top, top + 3, y), 1 - c * 0.7, y * 0.4, col_speed,
         col_phase}
      end

    if streak == nil and star == nil and rain == nil,
      do: {:fixed, cr, cg, cb, floor, 1},
      else: {:sky, cr, cg, cb, floor, streak, star, rain}
  end

  defp kind(@plain, _x, _r, _y, {cr, cg, cb, _c, _floor}, _star, _columns),
    do: {:plain, cr, cg, cb}

  defp kind(@field, x, r, y, {cr, _cg, _cb, _c, _floor}, _star, _columns) do
    # The gold glint just under the horizon.
    g = cr - 0.06
    p = (y - @hz) / (@h - @hz)
    q = (x - @sun_x) / 100
    sun_w = :math.exp(-(q * q))
    east = smooth(80, 130, x + 10 * p)
    fore = 1 - 0.6 * smooth(@h - 22, @h - 2, y)
    light = fround((0.72 + 0.45 * sun_w) * (1 - 0.35 * east) * fore)
    persp = fround((x + 0.5 - @vx) * 24 / (r + 2 - @hz) + 256)
    {:field, {x * 0.05, r * 0.17}, persp, light, {0.9 * g, 0.48 * g, 0.12 * g}}
  end

  defp kind(@road, x, r, y, _static, _star, _columns) do
    p = (y - @hz) / (@h - @hz)
    q = (x - @sun_x) / 110
    sun = 0.5 + 0.5 * :math.exp(-(q * q))
    rut = if abs(abs(x + 0.5 - road_c(p)) - road_w(p) * 0.45) < 0.4 + p * 0.8, do: 0.6, else: 1
    l = (0.6 + 0.3 * noise(x * 0.5, r * 0.5, 0)) * sun * rut * (1 - 0.65 * p)
    {:fixed, 0.08 + 0.42 * l, 0.06 + 0.3 * l, 0.07 + 0.26 * l, 0.05, smooth(@h + 10, @h - 8, y)}
  end

  # Far trees: dark, hazed toward the rain.
  defp kind(@belt, x, _r, _y, _static, _star, _columns) do
    h = smooth(130, 190, x)
    {:fixed, mix(0.07, 0.1, h), mix(0.05, 0.1, h), mix(0.1, 0.17, h), 0.06, 1}
  end

  defp kind(@tree, x, _r, y, _static, _star, _columns) do
    rim = noise(x * 0.6, y * 0.6, 0)
    {:fixed, 0.06 + 0.06 * rim, 0.04 + 0.03 * rim, 0.07 + 0.04 * rim, 0.03, 1}
  end

  # Back-lit by the afterglow: a dark silhouette with a warm western rim.
  defp kind(m, x, _r, _y, _static, _star, _columns) when m in [@house, @pump] do
    rim = if m == @house and x == @hx0, do: 0.18, else: 0
    {:fixed, 0.07 + rim, 0.05 + rim * 0.55, 0.09 + rim * 0.3, 0.03, 1}
  end

  defp kind(@roof, _x, _r, _y, _static, _star, _columns), do: {:fixed, 0.1, 0.06, 0.1, 0.03, 1}

  defp kind(@pane, x, _r, _y, _static, _star, _columns),
    do: {:pane, if(x < 46, do: 0.6, else: 1)}

  # The lit pane's glow on the yard and the wall around it.
  defp pane_glow(@pane, _x, _y), do: nil

  defp pane_glow(_m, x, y) do
    lx = x + 0.5 - 50.5
    ly = y - (@hw0 + 3.5)

    if lx * lx + ly * ly < 200,
      do: :math.exp(-:math.sqrt(lx * lx + ly * ly * 2) / 3) * 0.5
  end

  # The windpump's wheel, turning slowly, and its tail vane: whether the
  # cell is on the wheel's ring, near its hub, its angle, and on the vane.
  defp wheel(x, y, pump_y) do
    wx = x + 0.5 - @pump_x
    wy = y - pump_y

    if wx > -4 and wx < 7 and wy > -4 and wy < 4 do
      wd = :math.sqrt(wx * wx + wy * wy)

      {wd < 3.6 and wd > 0.4, wd < 1, :math.atan2(wy, wx), wy > -1 and wy < 0.6 and wx > 2}
    end
  end

  # --- the halftone ----------------------------------------------------------

  # Dot size from brightness, with a little jitter against contour lines.
  # A small dot is drawn brighter, a large one dimmer, so a gradient stays
  # smooth across the steps; the darkest stay dark.
  defp dot(x, r, cr, cg, cb, floor, fade, jit) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(floor + (1 - floor) * peak * 0.97 + jit) * fade
    step = max(0, min(3, JSMath.round(level * 3 + elem(@bayer, band(r, 3) * 4 + band(x, 3)))))
    want = if step != 0, do: min(1, (level + 0.04) / elem(@cover, step)), else: 0
    s = min(0.14 + 0.86 * want, 0.45 + 0.8 * level) / peak
    {step, clamp(cr * s), clamp(cg * s), clamp(cb * s)}
  end

  # The dot of a still cell: its character, and its colour as the palette
  # lookup takes it (the cache key, then the colour).
  defp halftone_static(x, r, cr, cg, cb, floor, fade, jit) do
    {step, tr, tg, tb} = dot(x, r, cr, cg, cb, floor, fade, jit)
    {elem(@dots, step), key(tr, tg, tb), tr, tg, tb}
  end

  defp halftone(x, r, cr, cg, cb, floor, fade, jit, color?, lut) do
    {step, tr, tg, tb} = dot(x, r, cr, cg, cb, floor, fade, jit)

    if color? do
      {i, lut} = lookup(lut, key(tr, tg, tb), tr, tg, tb)
      {elem(@dots, step), i, lut}
    else
      {elem(@dots, step), 0, lut}
    end
  end

  defp paint({ch, key, tr, tg, tb}, true, lut) do
    {i, lut} = lookup(lut, key, tr, tg, tb)
    {ch, i, lut}
  end

  defp paint({ch, _key, _tr, _tg, _tb}, false, lut), do: {ch, 0, lut}

  # The nearest-colour cache's key, as `AsciiArt.Kit.Palette.nearest/4` makes it.
  defp key(r, g, b), do: bsl(cube(r), 10) ||| bsl(cube(g), 5) ||| cube(b)
  defp cube(v), do: min(31, trunc(v * 31.99))

  defp lookup({_palette, answers} = lut, key, tr, tg, tb) do
    case answers do
      %{^key => i} -> {i, lut}
      _ -> Palette.nearest(lut, tr, tg, tb)
    end
  end

  # --- lightning -------------------------------------------------------------

  # A fixed schedule of flashes, some carrying a bolt, as {intensity, inside,
  # centre x, centre y, the bolt's brightness, the bolt's distances}.
  defp flash(t, bolts) do
    n = floor(t / @period)
    start = if n == 0, do: -0.08, else: n * @period + 0.2 + hash(n, 51) * 1.6
    l = t - start

    # Some periods stay dark.
    if (n > 0 and hash(n, 50) < 0.25) or l < 0 or l > 0.9 do
      nil
    else
      # A stroke and its restrikes, each a sharp rise and a fast decay.
      strikes = [{0, 0.09, 1}, {0.09 + hash(n, 52) * 0.06, 0.06, 0.7 - 0.15}]
      strikes = strikes ++ [{0.32 + hash(n, 53) * 0.2, 0.06, 0.7 - 2 * 0.15}]

      i =
        Enum.reduce(strikes, 0, fn {s, d, a}, i ->
          if l >= s, do: i + :math.exp(-(l - s) / d) * a, else: i
        end)

      bolt = if n == 0 or hash(n, 54) > 0.55, do: elem(bolts, rem(n, 4))

      case bolt do
        {bx, field} ->
          {min(1.3, i), 0, bx, @base - 8, if(l < 0.5, do: min(1, i * 1.4), else: 0), field}

        nil ->
          {min(1.3, i), 0, 115 + hash(n, 55) * 45, 14 + hash(n, 56) * 24, 0, nil}
      end
    end
  end

  # Between the big flashes, the storm keeps flickering inside itself.
  defp flicker(t) do
    n0 = floor(t / @fl)
    Enum.find_value([n0, n0 - 1], fn n -> if n >= 0, do: flicker(t, n) end)
  end

  defp flicker(t, n) do
    l = t - (n * @fl + 0.35 + hash(n, 70) * 0.75)

    if l >= 0 and l <= 0.6 do
      pulses = [{0, 1}, {0.08 + hash(n, 71) * 0.1, 0.7}, {0.26 + hash(n, 72) * 0.18, 0.45}]

      i =
        Enum.reduce(pulses, 0, fn {p, a}, i ->
          if l >= p, do: i + :math.exp(-(l - p) / 0.07) * a, else: i
        end)

      {min(1, i) * (0.25 + 0.2 * hash(n, 73)), 1, 120 + hash(n, 74) * 38, 15 + hash(n, 75) * 25,
       0, nil}
    end
  end

  # --- the near ears ---------------------------------------------------------

  # Each stalk bends from its foot, more at the tip, and the gusts that roll
  # across the field push them further. As %{row => %{column => value}}:
  # above 0 a lit grain head, below 0 a dark stalk; stored as upstream's
  # Float32Array stores them.
  defp ear_map(ears, t, g_off, gusts) do
    gust = elem(gusts, @h - 1 - @hz)
    shift = floor(g_off * 1.5)

    Enum.reduce(ears, %{}, fn {ex, eh, ph, foot, hl}, map ->
      gu = elem(gust, Integer.mod(trunc(ex) - shift, @gw))
      # The inflow blows toward the storm, so every ear bows a little east.
      lean = 0.7 + 0.7 * :math.sin(t * 1.7 + ph) + 1.8 * gu
      ear({ex, eh, foot, hl, lean, eh + hl}, 0, map)
    end)
  end

  defp ear({_ex, _eh, _foot, _hl, _lean, tall}, i, map) when i >= tall, do: map

  defp ear({ex, eh, foot, hl, lean, tall} = ear, i, map) do
    y = JSMath.round(@h + foot - i)
    q = i / tall
    x = JSMath.round(ex + lean * q * q)

    map =
      cond do
        y >= @h or x < 0 or x + 1 >= @w -> map
        # The stalk: a thin dark line against the field.
        i < eh -> if ear_at(map, y, x) == 0, do: put_ear(map, y, x, -1), else: map
        true -> head(map, y, x, i - eh, hl, lean)
      end

    ear(ear, i + 1, map)
  end

  # The head: plump, two grains wide in the middle, tapering at both ends,
  # the grains alternating side to side.
  defp head(map, y, x, j, hl, lean) do
    tip = j == hl - 1

    v =
      cond do
        tip -> 0.55
        j == 0 -> 0.7
        true -> 1 - 0.18 * band(trunc(j), 1)
      end

    map = if v > ear_at(map, y, x), do: put_ear(map, y, x, v), else: map

    map =
      if not tip and j > 0 and v * 0.82 > ear_at(map, y, x + 1),
        do: put_ear(map, y, x + 1, v * 0.82),
        else: map

    # A whisker of awns past the tip.
    a = x + if(lean > 0.5, do: 1, else: 0)

    if tip and y > 0 and ear_at(map, y - 1, a) < 0.3,
      do: put_ear(map, y - 1, a, 0.3),
      else: map
  end

  defp ear_at(map, y, x) do
    case map do
      %{^y => %{^x => v}} -> v
      _ -> 0
    end
  end

  defp put_ear(map, y, x, v),
    do: Map.update(map, y, %{x => fround(v)}, &Map.put(&1, x, fround(v)))

  # --- the frame -------------------------------------------------------------

  @impl true
  def frame(state, t, env) do
    f = flash(t, state.bolts)
    fl = flicker(t)
    f = if fl != nil and (f == nil or elem(f, 0) < elem(fl, 0)), do: fl, else: f
    g_off = t * 9

    # Lightning, when bright enough to show: and how far back it lights each
    # column.
    f =
      case f do
        {i, inside, cx, cy, on, field} when i > 0.01 ->
          backs = List.to_tuple(for x <- 0..(@w - 1), do: :math.exp(-abs(x - cx) / 34))
          {i, inside, cx, cy, on, field, backs}

        _ ->
          nil
      end

    fr = {t, t * 1.2, t * 0.9, :math.sin(t * 3.7), f}
    ears = ear_map(state.ears, t, g_off, state.gusts)

    {lines, lut} =
      Enum.map_reduce(0..(@h - 1), state.lut, fn r, lut ->
        row = elem(state.rows, r)
        p = elem(row, 1)

        gust =
          if r >= @hz,
            do: {elem(state.gusts, r - @hz), floor(g_off * (0.5 + p)), elem(state.wheat, r - @hz)}

        ctx = {r, row, gust, elem(state.streaks, min(r, @hz - 1)), Map.get(ears, r), fr, state}
        line(0, elem(state.cells, r), ctx, env.color?, lut, <<>>, <<>>)
      end)

    text = lines |> Enum.map(&elem(&1, 0)) |> Enum.intersperse(?\n)
    colors = if env.color?, do: IO.iodata_to_binary(Enum.map(lines, &elem(&1, 1)))
    {text, colors, %{state | lut: lut}}
  end

  defp line(@w, _cells, _ctx, _color?, lut, chars, colors), do: {{chars, colors}, lut}

  defp line(x, cells, ctx, color?, lut, chars, colors) do
    {ch, i, lut} = px(x, elem(cells, x), ctx, color?, lut)
    line(x + 1, cells, ctx, color?, lut, <<chars::binary, ch::binary>>, <<colors::binary, i>>)
  end

  defp px(
         x,
         {kind, common, still},
         {r, _row, _gust, _streak, ears, fr, _state} = ctx,
         color?,
         lut
       ) do
    e = if ears == nil, do: 0, else: Map.get(ears, x, 0)
    {_jit, _glow, wheel, _light} = common

    cond do
      e < 0 ->
        # A stalk: one unbroken line of the smallest dots in dark umber.
        {elem(@dots, 1), @stalk, lut}

      still != nil and e == 0 and wheel == nil and elem(fr, 4) == nil ->
        paint(still, color?, lut)

      true ->
        {cr, cg, cb, floor, fade, rain} = material(kind, x, ctx)
        shade(x, r, e, {cr, cg, cb, floor, fade, rain}, common, ctx, color?, lut)
    end
  end

  defp shade(x, r, e, {cr, cg, cb, floor, fade, rain}, common, ctx, color?, lut) do
    {jit, glow, wheel, light} = common
    {_r, {y, _p, _contrast, _fade}, _gust, _streak, _ears, fr, _state} = ctx
    {t, _drift, _shaft, _sin37, f} = fr

    {cr, cg, cb, floor, fade} =
      if e > 0 do
        # A grain head, warm and brightest on its sunward edge.
        q = (x - @sun_x) / 120
        l = e * (0.5 + 0.5 * :math.exp(-(q * q)))
        {0.95 * l, 0.68 * l, 0.3 * l, 0.1, 1}
      else
        {cr, cg, cb, floor, fade}
      end

    {cr, cg, cb, floor} = turn(wheel, t, cr, cg, cb, floor)
    {cr, cg, cb} = glow(glow, cr, cg, cb)
    {cr, cg, cb} = strike(f, x, y, r, light, rain, cr, cg, cb)
    halftone(x, r, cr, cg, cb, floor, fade, jit, color?, lut)
  end

  # The windpump's wheel and its vane.
  defp turn(nil, _t, cr, cg, cb, floor), do: {cr, cg, cb, floor}

  defp turn({ring, hub, ang, vane}, t, cr, cg, cb, floor) do
    {cr, cg, cb, floor} =
      if ring and (:math.cos((ang - t * 1.6) * 8) > 0.2 or hub),
        do: {0.07, 0.05, 0.09, 0.03},
        else: {cr, cg, cb, floor}

    if vane, do: {0.07, 0.05, 0.09, 0.03}, else: {cr, cg, cb, floor}
  end

  defp glow(nil, cr, cg, cb), do: {cr, cg, cb}
  defp glow(lg, cr, cg, cb), do: {cr + lg, cg + lg * 0.66, cb + lg * 0.25}

  # Lightning: the cloud glows from inside; the base and the rain are lit
  # from behind; a full flash reaches the land as well.
  defp strike(nil, _x, _y, _r, _light, _rain, cr, cg, cb), do: {cr, cg, cb}

  defp strike(f, x, y, r, {sky?, cloud, dark}, rain, cr, cg, cb) do
    {i, inside, cx, cy, bolt_on, field, backs} = f
    dx = x - cx
    dy = (y - cy) * 1.3
    dist = :math.sqrt(dx * dx + dy * dy)
    c = if sky?, do: cloud, else: 0

    inner =
      cond do
        inside == 0 -> :math.exp(-dist / 16) * (0.3 + 0.7 * c) * i * 1.3
        c == 0 -> 0
        true -> :math.exp(-dist / 14) * c * i * 2
      end

    back =
      if sky?,
        do: (dark * 0.5 + rain * 0.8) * elem(backs, x) * i * if(inside != 0, do: 0.5, else: 1),
        else: 0

    amb = if inside != 0, do: 0, else: i * if(sky?, do: 0.08, else: 0.05)
    lw = inner + back
    cr = cr + (0.75 * lw + amb * 0.8)
    cg = cg + (0.72 * lw + amb * 0.8)
    cb = cb + (1.0 * lw + amb)
    bolt(bolt_on, field, x, y, r, c, cr, cg, cb)
  end

  defp bolt(on, _field, _x, _y, _r, _c, cr, cg, cb) when on == 0, do: {cr, cg, cb}

  defp bolt(on, field, x, y, r, c, cr, cg, cb) do
    d =
      case elem(field, r) do
        nil -> 99
        row -> elem(row, x)
      end

    if d < 12 and (c < 0.6 or y > @base - 1) do
      core = smooth(1.1, 0.35, d) * on
      glow = (:math.exp(-d / 2) * 0.55 + :math.exp(-d / 7) * 0.2) * on
      {cr + (core + glow * 0.75), cg + (core + glow * 0.72), cb + (core + glow)}
    else
      {cr, cg, cb}
    end
  end

  # --- each kind's colour in a frame -----------------------------------------

  defp material({:fixed, cr, cg, cb, floor, fade}, _x, _ctx), do: {cr, cg, cb, floor, fade, 0}

  defp material({:plain, cr, cg, cb}, x, {_r, _row, {gust, shift, _wheat}, _, _, _, _}) do
    gu = elem(gust, Integer.mod(x - shift, @gw))
    v = 0.75 + 0.45 * gu
    {cr * v, cg * v, cb * v, 0.05, 1, 0}
  end

  defp material({:field, {x005, r017}, persp, light, {g9, g48, g12}}, x, ctx) do
    {_r, {_y, _p, contrast, fade}, {gust, shift, wheat}, _streak, _ears, fr, _state} = ctx
    t = elem(fr, 0)
    gu = elem(gust, Integer.mod(x - shift, @gw))
    # Stalks lean with the gust and spring back.
    sway = 0.5 * :math.sin(t * 2.1 + x005 + r017) + 2.2 * gu
    u = persp + sway
    ui = floor(u)
    uf = u - ui
    a0 = elem(wheat, band(ui, 511))
    tex = a0 + (elem(wheat, band(ui + 1, 511)) - a0) * uf
    v = clamp(0.55 + (tex - 0.5) * contrast)
    l = (v * 0.7 + 0.4 * gu) * light
    {0.04 + 0.7 * l + g9, 0.03 + 0.48 * l + g48, 0.035 + 0.18 * l + g12, 0.05, fade, 0}
  end

  defp material({:pane, small}, x, {_r, _row, _gust, _streak, _ears, fr, _state}) do
    {t, _drift, _shaft, sin37, _f} = fr
    g = 0.88 + 0.12 * :math.sin(t * 2.3 + x) * sin37
    {g * small, 0.72 * g * small, 0.3 * g * small, 0.3, 1, 0}
  end

  defp material({:sky, cr, cg, cb, floor, streak, star, rain}, x, ctx) do
    {_r, _row, _gust, streaks, _ears, fr, state} = ctx
    {t, drift, shaft_off, _sin37, _f} = fr
    {cr, cg, cb} = streak(streak, streaks, x, drift, cr, cg, cb)
    {cr, cg, cb} = star(star, t, cr, cg, cb)
    {cr, cg, cb, rain} = rain(rain, state.shafts, t, shaft_off, cr, cg, cb)
    {cr, cg, cb, floor, 1, rain}
  end

  # The altostratus, lit gold toward the sun.
  defp streak(nil, _streaks, _x, _drift, cr, cg, cb), do: {cr, cg, cb}

  defp streak({clear, fade, sun}, streaks, x, drift, cr, cg, cb) do
    sx = x + drift
    ix = floor(sx)
    fx = sx - ix
    s0 = elem(streaks, rem(ix, @cw))
    s = (s0 + (elem(streaks, rem(ix + 1, @cw)) - s0) * fx) * clear * fade * 0.75

    if s > 0.005,
      do:
        {mix(cr, 0.5 + 0.5 * sun, s), mix(cg, 0.24 + 0.36 * sun, s),
         mix(cb, 0.34 + 0.06 * sun, s)},
      else: {cr, cg, cb}
  end

  defp star(nil, _t, cr, cg, cb), do: {cr, cg, cb}

  defp star({ph, sp, a, clear}, t, cr, cg, cb) do
    v = fround(a * (0.55 + 0.45 * :math.sin(t * sp + ph))) * clear
    {max(cr, v * 0.9), max(cg, v * 0.88), max(cb, v)}
  end

  # Rain curtains hanging from the shelf to the ground: falling streaks,
  # slanted with the shafts.
  defp rain(nil, _shafts, _t, _shaft_off, cr, cg, cb), do: {cr, cg, cb, 0}

  defp rain({xs, on, sm, clear, y04, speed, phase}, shafts, t, shaft_off, cr, cg, cb) do
    ui = Integer.mod(floor(xs - shaft_off), @rw)
    env = elem(shafts, ui) * on * sm * clear

    if env > 0.01 do
      fall = JSMath.mod(y04 - t * speed * 0.1 + phase + 1000, 4)
      lit = if fall < 1.4, do: 1, else: 0

      {mix(cr, 0.06 + 0.07 * lit, env * 0.88), mix(cg, 0.065 + 0.075 * lit, env * 0.88),
       mix(cb, 0.12 + 0.1 * lit, env * 0.88), env}
    else
      {cr, cg, cb, 0}
    end
  end
end
