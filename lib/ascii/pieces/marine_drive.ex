defmodule Ascii.Pieces.MarineDrive do
  @moduledoc """
  Mumbai's queen's necklace at night, lamps curving round the bay.

  The queen's necklace seen from malabar hill at night. A string of sodium
  lamps sweeps round the bay to the towers at nariman point, cars trail light
  along the road beneath them, and the bay carries their long wavering
  reflections. Ships ride at anchor on the horizon.

  Shaded in colour cell by cell, then drawn as a halftone: a dot whose size is
  the cell's brightness, ordered-dithered, in the palette colour nearest its
  hue. Everything along the curve is placed by distance along it, so
  buildings, lamps and cars shrink together toward the point.

  Ported from `src/pieces/marine-drive.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Hash, Palette, Scene}
  import Bitwise

  @meta %Ascii.Meta{
    name: "marine drive",
    category: :scenes,
    note: "mumbai's queen's necklace at night, lamps curving round the bay",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#07080f",
    palette: [
      "#18213f",
      "#202c55",
      "#2a396d",
      "#374a88",
      "#4a60a2",
      "#6880bc",
      "#2c2140",
      "#3f2d58",
      "#56396b",
      "#6e4a7a",
      "#8a5f88",
      "#5a2e3c",
      "#7b404c",
      "#9e5858",
      "#55300f",
      "#7d4515",
      "#a95c1b",
      "#d27a24",
      "#ee9631",
      "#ffb246",
      "#ffcd6a",
      "#ffe39c",
      "#fff2cf",
      "#ffffff",
      "#dce6ff",
      "#a9bde8",
      "#6a181b",
      "#b22a28",
      "#ff4b3e",
      "#132c38",
      "#1c3f4f",
      "#2a5868",
      "#29283a",
      "#3c3a4c",
      "#565266",
      "#79738a"
    ]
  }

  @w 200
  @h 100
  # The sea horizon.
  @hz 40
  # Nariman point, where the necklace ends.
  @tip 176
  @moon_x 189
  @moon_y 13
  @moon_r 4.5
  # Darker seas on the moon's face: {dx, dy, radius}.
  @maria [{-1.4, -1.2, 1.6}, {1.3, 0.8, 1.4}, {-0.6, 2, 1.1}]
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()
  # Sodium light: {1, 0.56, 0.18}; its red, times 1, is left out of the sums.
  @s1 0.56
  @s2 0.18

  @sky 0
  @water 1
  @far 2
  @tower 3
  @front 4
  @road 5
  @wall 6
  @pole 7
  @ship 8

  # Distance along the drive is tabulated every STEP columns.
  @step 0.25
  @n_u ceil((@tip + 4) / @step) + 2

  # One lamp near us is failing.
  @flick 6

  # Towers behind, a cluster at the point: {centre, half width, top row, warm light}.
  @towers [
    {24, 4.5, 21, 0},
    {97, 2.5, 27, 1},
    {107, 2, 22, 0},
    {118, 3, 30, 0},
    {126, 2, 25, 1},
    {136, 3, 23, 0},
    {142.5, 2, 15, 1},
    {149, 3.5, 27, 0},
    {156, 2.5, 19, 0},
    {162, 3, 12, 1},
    {168.5, 2.5, 21, 0},
    {173, 2, 28, 1}
  ]

  # Ships riding at anchor beyond the point, {x, row, r, g, b}: white
  # mastheads, warm deck and cabin lights, a red port light; a long freighter
  # with its bridge aft, and a smaller boat further out.
  @ship_lights [
    {184, 35, 1, 1, 1},
    {190, 34, 1, 1, 1},
    {185, 37, 1, 0.78, 0.45},
    {187, 37, 1, 0.8, 0.5},
    {189, 36, 1, 0.82, 0.5},
    {191, 36, 1, 0.8, 0.5},
    {197, 36, 1, 1, 1},
    {196, 38, 1, 0.78, 0.45},
    {199, 38, 0.95, 0.22, 0.18}
  ]

  # Low stratus, lit from beneath by the city; it wraps every CW columns.
  @cw 800
  # Cars are binned along the drive.
  @bin 0.2
  @u0 -6
  # The dot's power is bounded from a table below POW_TOP, GRAIN steps a unit.
  @grain 1024
  @pow_top 4

  @impl true
  def meta, do: @meta

  # Called for nearly every cell: local, so they inline.
  @compile {:inline,
            clamp: 1,
            smooth: 3,
            mix: 3,
            js_round: 1,
            noise: 2,
            bilerp: 6,
            lerp: 3,
            level: 3,
            step: 2,
            want: 2}
  # Floats out, so the shading stays in float arithmetic.
  defp clamp(v) when v < 0, do: 0.0
  defp clamp(v) when v > 1, do: 1.0
  defp clamp(v), do: v

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  # `Math.round`, as `Ascii.JSMath.round/1` does it for a float.
  defp js_round(x) do
    c = ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end

  defp f32(v), do: JSMath.fround(v)
  defp sq(v), do: v * v

  defdelegate fbm(x, y, octaves, period), to: Scene

  # --- the shore ---------------------------------------------------------------

  # The shoreline: steep and near at the left, flat and far toward the point.
  defp shore(x), do: 50 + 34 * :math.pow(max(0, 1 - x / @tip), 2.2)
  # How large one unit of distance along the drive looks at column x.
  defp sc(x), do: 0.5 + 1.9 * :math.pow(max(0, 1 - x / @tip), 1.5)
  defp sea_top(x) when x <= @tip, do: shore(x)
  defp sea_top(x), do: max(@hz, 50 - (x - @tip) * 1.6)
  defp wall_top(x), do: shore(x) - max(1, sc(x))
  defp road_top(x), do: wall_top(x) - max(1, 1.5 * sc(x))

  # The city's sodium glow in the sky, weaker out over the open sea.
  defp glow(x, y) do
    over = 0.5 + 0.5 * smooth(@tip + 24, @tip - 16, x)
    h = max(0, @hz - y)
    over * (:math.exp(-h / 4) * 0.5 + :math.exp(-h / 12) * 0.12)
  end

  # Distance along the drive.
  defp u_table do
    {us, _} =
      Enum.map_reduce(1..(@n_u - 1), 0.0, fn i, prev ->
        x = (i - 0.5) * @step
        sl = (shore(x + 0.05) - shore(x - 0.05)) / 0.1
        u = f32(prev + :math.sqrt(1 + sl * sl) * @step / sc(x))
        {u, u}
      end)

    List.to_tuple([0.0 | us])
  end

  defp u_of(table, x) do
    f = max(0, min(@n_u - 1.001, x / @step))
    i = trunc(f)
    a = elem(table, i)
    a + (elem(table, i + 1) - a) * (f - i)
  end

  defp x_of_u(table, u) do
    {lo, hi} =
      Enum.reduce(1..30, {0, @tip}, fn _, {lo, hi} ->
        m = (lo + hi) / 2
        if u_of(table, m) < u, do: {m, hi}, else: {lo, m}
      end)

    (lo + hi) / 2
  end

  # The lamps: {x, the lamp's row, scale}.
  defp lamps(table, uend) do
    0.6
    |> Stream.iterate(&(&1 + 3.75))
    |> Enum.take_while(&(&1 < uend - 0.4))
    |> Enum.map(fn u ->
      lx = x_of_u(table, u)
      s = sc(lx)
      {lx, wall_top(lx) - 2.4 * s, s}
    end)
  end

  # The front row: art deco blocks along the drive, {u0, u1, floors, tone, crown}.
  defp buildings(uend) do
    {-4, 0}
    |> Stream.unfold(fn
      {u, _i} when u >= uend ->
        nil

      {u, i} ->
        w = 7 + 7 * Hash.scene(i, 21)
        # Art deco blocks of five to eight storeys, and towers at the near, hilly end.
        tall = JSMath.round(7 * smooth(26, 2, u) * (0.6 + 0.4 * Hash.scene(i, 26)))

        {{u, u + w, 5 + floor(Hash.scene(i, 22) * 4) + tall, 0.75 + 0.5 * Hash.scene(i, 23),
          Hash.scene(i, 24) > 0.45}, {u + (w + 0.4 + 1.8 * Hash.scene(i, 25)), i + 1}}
    end)
    |> Enum.to_list()
  end

  # --- the still picture -------------------------------------------------------

  # A cell above the water: {material, r, g, b, floor, lane, sky glow}, with
  # the rooms whose light changes and the aviation lights it adds.
  defp picture(x, r, ctx) do
    xc = x + 0.5
    y = r + 0.5

    if y >= sea_top(xc) do
      {{@water, 0.0, 0.0, 0.0, 0.0, 0, 0.0}, [], []}
    else
      cell = far_city(x, r, xc, y)
      {cell, beacons} = towers(cell, r * @w + x, r, xc, y)
      {{m, cr, cg, cb, fl}, lane, flicks} = drive(cell, x, r, xc, y, ctx)

      {{m, cr, cg, cb}, sky_glow} =
        if m == @sky, do: sky(x, r, xc, y), else: {{m, cr, cg, cb}, 0}

      {{m, f32(cr), f32(cg), f32(cb), f32(fl), lane, f32(sky_glow)}, flicks, beacons}
    end
  end

  # The far city: low blocks in the haze, pricked with tiny lights.
  defp far_city(x, r, xc, y) do
    blk = floor((x + 40 * fbm(x * 0.02, 5, 2, 0)) / 3)

    far_top =
      @hz - 0.4 -
        (0.4 + 5 * :math.pow(Hash.scene(blk, 7), 3)) * (0.5 + 0.5 * fbm(x * 0.05, 2, 2, 0))

    if xc < @tip + 7 and y >= far_top do
      g = glow(xc, @hz - 2)
      cr = 0.03 + 0.05 * g
      cg = 0.04 + 0.03 * g
      cb = 0.08 + 0.02 * g

      if Hash.scene(x * 3 + 1, r * 7 + 2) < 0.035 do
        v = 0.25 + 0.45 * Hash.scene(x, r * 5 + 9)

        if Hash.scene(x * 5, r) < 0.3,
          do: {@far, cr + v * 0.8, cg + v * 0.85, cb + v, 0.08},
          else: {@far, cr + v, cg + v * 0.7, cb + v * 0.4, 0.08}
      else
        {@far, cr, cg, cb, 0.08}
      end
    else
      {@sky, 0, 0, 0, 0.15}
    end
  end

  defp towers(cell, k, r, xc, y) do
    @towers
    |> Enum.with_index()
    |> Enum.reduce({cell, []}, fn {{tx, hw, top, warm}, ti}, {cell, beacons} ->
      dx = xc - tx

      if abs(dx) > hw or y < top do
        {cell, beacons}
      else
        # Dark glass, its moonward edge catching a little light.
        {cr, cg, cb} =
          if dx > hw - 1,
            do: {0.015 + 0.04, 0.018 + 0.055, 0.035 + 0.1},
            else: {0.015, 0.018, 0.035}

        g = glow(xc, y) * 0.2
        rgb = {cr + g * 0.42, cg + g * 0.21, cb + g * 0.1}
        {cr, cg, cb} = tower_floor(rgb, ti, r - top, r, xc, tx, hw, warm)

        beacons =
          if r - top == 0 and abs(dx) < 0.6 and top < 20,
            do: [{k - @w, ti * 1.7} | beacons],
            else: beacons

        {{@tower, cr, cg, cb, 0.03}, beacons}
      end
    end)
    |> then(fn {cell, beacons} -> {cell, Enum.reverse(beacons)} end)
  end

  # The rooftop's edge, and the lit floors.
  defp tower_floor({cr, cg, cb}, _ti, 0, _r, _xc, _tx, _hw, _warm),
    do: {cr + 0.08, cg + 0.1, cb + 0.16}

  defp tower_floor({cr, cg, cb} = rgb, ti, fr, r, xc, tx, hw, warm) do
    seg = floor((xc - tx + hw) / 3)
    h = Hash.scene(ti * 17 + seg, r * 13 + 3)

    if fr > 0 and rem(fr, 2) == 1 and abs(xc - tx) < hw - 0.5 and h < 0.5 do
      v = 0.4 + 0.3 * Hash.scene(ti * 7 + seg, r)

      if if(warm != 0, do: h < 0.1, else: h > 0.1),
        do: {cr + v * 0.72, cg + v * 0.84, cb + v},
        else: {cr + v, cg + v * 0.72, cb + v * 0.42}
    else
      rgb
    end
  end

  defp drive(cell, _x, _r, xc, _y, _ctx) when xc > @tip, do: {cell, 0, []}

  defp drive(cell, x, r, xc, y, ctx) do
    s = sc(xc)
    wt = wall_top(xc)
    rt = road_top(xc)
    bi = elem(ctx.bld_at, x)

    {cell, flicks} =
      if bi >= 0 and y < rt,
        do: front(cell, x, r, y, {s, rt, bi, elem(ctx.blds, bi), elem(ctx.col_u, x)}),
        else: {cell, []}

    {cell, lane} =
      cond do
        y >= rt and y < wt ->
          lf = (y - rt) / (wt - rt)
          lane = if wt - rt < 1.8, do: 3, else: if(lf < 0.5, do: 1, else: 2)
          {{@road, 0.07, 0.05, 0.05, 0.1}, lane}

        # The sea wall and the promenade along it.
        y >= wt ->
          {{@wall, 0.1, 0.09, 0.1, 0.1}, 0}

        true ->
          {cell, 0}
      end

    pole? =
      Enum.any?(ctx.lamps, fn {lx, ly, ls} ->
        ls > 1.15 and abs(xc - lx) < 0.5 and y > ly and y < wt
      end)

    {if(pole?, do: {@pole, 0.09, 0.08, 0.09, 0.1}, else: cell), lane, flicks}
  end

  defp front(cell, x, r, y, {s, rt, bi, {u0, u1, floors, tone, crown}, col_u}) do
    uu = col_u - u0
    bw = u1 - u0
    # Height above the road, in storeys of 1.7.
    f = (rt - y) / s
    hgt = floors * 1.7 + 1.1
    hgt = if crown and uu > bw * 0.32 and uu < bw * 0.68, do: hgt + 1.6, else: hgt

    if f < hgt do
      t0 = tone * if(uu < 0.5 or uu > bw - 0.5, do: 1.35, else: 1)
      # Pale art deco plaster, warm where the street lamps reach it.
      up = :math.exp(-f / 2) * 0.16
      rgb = {0.03 * t0 + up, 0.035 * t0 + up * @s1, 0.06 * t0 + up * @s2}

      # The cornice, moonlit.
      rgb =
        if f > hgt - 0.6 / s or
             (f > floors * 1.7 + 0.6 and f < floors * 1.7 + 0.6 + 0.5 / s),
           do: add(rgb, 0.1, 0.13, 0.22),
           else: rgb

      # The corner toward the moon.
      rgb = if uu > bw - 0.7 / s - 0.2, do: add(rgb, 0.04, 0.06, 0.12), else: rgb
      {{cr, cg, cb}, flicks} = windows(rgb, x, r, f, uu, bw, s, bi, floors)
      {{@front, cr, cg, cb, 0.03}, flicks}
    else
      {cell, []}
    end
  end

  defp add({cr, cg, cb}, r, g, b), do: {cr + r, cg + g, cb + b}

  defp windows(rgb, x, r, f, uu, bw, s, bi, floors) do
    fi = floor((f - 0.9) / 1.7)
    ff = f - 0.9 - fi * 1.7
    col = floor((uu - 0.3) / 1.5)
    cu = uu - 0.3 - col * 1.5
    fine? = s * 1.7 >= 2.6

    in_win? =
      fi >= 0 and fi < floors and uu > 0.7 and uu < bw - 0.7 and
        (not fine? or (ff > 0.45 and ff < 1.35 and cu > 0.35 and cu < 1.15))

    cond do
      not in_win? ->
        {rgb, []}

      # Too far to count rooms: each storey reads as a band of light, broken
      # where rooms are dark.
      not fine? ->
        v = 0.04 + 0.26 * sq(Hash.scene(bi * 13 + floor(uu / 3.2), fi * 7 + 1))
        rgb = add(rgb, v, v * 0.8, v * 0.55)

        if Hash.scene(x * 7 + 3, r * 11) < 0.035,
          do: {add(rgb, 0.4, 0.36, 0.28), []},
          else: {rgb, []}

      Hash.scene(bi * 97 + col, fi * 31 + 5) < 0.3 ->
        v = 0.35 + 0.3 * Hash.scene(bi * 13 + col, fi)
        # Tungsten, paler than the lamps, or a tube light.
        {wr, wg, wb} =
          if Hash.scene(bi * 7 + col, fi * 3 + 1) < 0.25,
            do: {0.82, 0.9, 1},
            else: {1, 0.84, 0.58}

        rgb = add(rgb, v * wr, v * wg, v * wb)
        fk = Hash.scene(bi * 5 + col, fi * 11 + 7)

        if fk < 0.07,
          do:
            {rgb,
             [
               {r * @w + x, v * wr, v * wg, v * wb, if(fk < 0.025, do: 1, else: 0), 0.3 + fk * 9,
                fk * 400}
             ]},
          else: {rgb, []}

      true ->
        {cr, cg, cb} = rgb
        {{cr * 0.7, cg * 0.7, cb * 0.8}, []}
    end
  end

  # Navy overhead to a sodium haze on the horizon.
  defp sky(x, r, xc, y) do
    v = y / @hz
    # Brighter over the point, so its towers stand dark against the haze.
    g =
      glow(xc, y) * (1 + 0.6 * smooth(84, 98, xc) * smooth(186, 174, xc)) +
        0.2 * :math.exp(-max(0, @hz - y) / 14) * smooth(84, 104, xc) * smooth(188, 172, xc)

    veil = 0.88 + 0.24 * fbm(x * 0.05, r * 0.08, 3, 0)
    # The last of the blue hour, deepening overhead.
    vv = :math.pow(v, 1.4)
    cr = (0.03 + 0.07 * vv) * veil + g * 0.42
    cg = (0.05 + 0.12 * vv) * veil + g * 0.22
    cb = (0.15 + 0.24 * vv) * veil + g * 0.1
    # A pale sea haze on the open horizon, for the ships to sit against.
    hzn = :math.exp(-max(0, @hz - y) / 3.5) * smooth(172, 186, xc) * 0.16
    cr = cr + hzn * 0.6
    cg = cg + hzn * 0.7
    cb = cb + hzn * 0.95
    # A hazy moon over the open sea.
    dmx = xc - @moon_x
    dmy = y - @moon_y
    dm = :math.sqrt(dmx * dmx + dmy * dmy)
    halo = :math.exp(-dm / 22) * 0.13 + :math.exp(-dm / 6) * 0.26
    cr = cr + halo * 0.9
    cg = cg + halo * 0.86
    cb = cb + halo * 0.8
    # A darker ring just off the limb, so the disc's edge pops.
    ring = 0.03 * smooth(4.6, 5.6, dm) * smooth(8.5, 6.5, dm)
    rgb = {cr - ring, cg - ring, cb - ring * 0.8}
    {cr, cg, cb} = if dm < @moon_r, do: moon(rgb, x, r, dmx, dmy, dm), else: rgb
    {{@sky, cr, cg, cb}, g}
  end

  defp moon({cr, cg, cb}, x, r, dmx, dmy, dm) do
    face =
      Enum.reduce(@maria, 0.9 + 0.1 * fbm(x * 0.6, r * 0.6, 2, 0), fn {mx, my, mr}, face ->
        d2 = (sq(dmx - mx) + sq(dmy - my)) / (mr * mr)
        if d2 < 1, do: face - 0.14 * (1 - d2), else: face
      end)

    a = smooth(@moon_r, @moon_r - 0.8, dm)
    {mix(cr, face, a), mix(cg, face * 0.95, a), mix(cb, face * 0.86, a)}
  end

  defp hull?(x, r) do
    (r >= 38 and x >= 182 and x <= 192) or (r == 37 and x >= 183 and x <= 192) or
      (r >= 35 and r <= 36 and x >= 189 and x <= 191) or (r >= 35 and r <= 36 and x == 184) or
      (r >= 38 and x >= 195 and x <= 199) or (r == 37 and x >= 196 and x <= 197)
  end

  defp ships(cells) do
    hulls =
      for r <- 34..39, x <- 180..(@w - 1), hull?(x, r) do
        {r * @w + x, {0.002, 0.002, 0.004, 0}}
      end

    lights = for {x, r, cr, cg, cb} <- @ship_lights, do: {r * @w + x, {cr, cg, cb, 0.1}}

    Enum.reduce(hulls ++ lights, cells, fn {k, {cr, cg, cb, fl}}, cells ->
      {_m, _, _, _, _, lane, sky_glow} = elem(cells, k)
      put_elem(cells, k, {@ship, f32(cr), f32(cg), f32(cb), f32(fl), lane, sky_glow})
    end)
  end

  # --- lamp light ----------------------------------------------------------------

  # Each lamp: a hot core, a halo and a wide warm spill, added up in
  # single precision lamp by lamp; and its reflection, a long column broken
  # by the swell, reaching toward us.
  defp lamp_light(lamps, cells) do
    lamps
    |> Enum.with_index()
    |> Enum.reduce({%{}, %{}, %{}}, fn {{lx, _ly, s} = lamp, j}, {lit, hot, refl} ->
      key = if j == @flick, do: :flick, else: :lamp
      {lit, hot} = lamp_glow(lamp, key, cells, lit, hot)

      # Its reflection.
      sy = shore(lx)
      wj = 0.4 + 0.7 * s
      len = 2 + 8 * s
      x0 = max(0, floor(lx - 3 * wj - 1))

      refl =
        Enum.reduce_while(floor(sy)..(@h - 1)//1, refl, fn r, refl ->
          dy = r + 0.5 - sy
          a = :math.exp(-dy / (len * 1.7)) * (0.3 + 0.15 * s) * smooth(-0.5, 1.5, dy)

          cond do
            dy < 0 ->
              {:cont, refl}

            a < 0.004 ->
              {:halt, refl}

            true ->
              {:cont,
               x0..(@w - 1)//1
               |> Enum.take_while(&(&1 < lx + 3 * wj + 1))
               |> Enum.reduce(refl, fn x, refl ->
                 k = r * @w + x

                 if water?(cells, k) do
                   g = a * :math.exp(-sq((x + 0.5 - lx) / wj))

                   if key == :flick,
                     do: add_refl(refl, k, 0, 0, 0, g),
                     else: add_refl(refl, k, g, g * @s1, g * @s2, 0)
                 else
                   refl
                 end
               end)}
          end
        end)

      {lit, hot, refl}
    end)
  end

  defp lamp_glow({lx, ly, s}, key, cells, lit, hot) do
    core = 0.34 + 0.3 * s
    halo = 0.4 + 0.4 * s
    spill = 1.2 + 1.5 * s
    reach = ceil(spill * 3.2)

    for r <- max(0, floor(ly - reach))..(@h - 1)//1,
        r < ly + reach,
        x <- max(0, floor(lx - reach))..(@w - 1)//1,
        x < lx + reach,
        k = r * @w + x,
        not water?(cells, k),
        reduce: {lit, hot} do
      {lit, hot} ->
        dx = x + 0.5 - lx
        dy = r + 0.5 - ly
        d = :math.sqrt(dx * dx + dy * dy)
        c = :math.exp(-sq(d / core)) * 2.2
        i = c * 0.7 + :math.exp(-d / halo) * 0.24 + :math.exp(-d / spill) * 0.02

        {Map.update(lit, {key, k}, f32(i), &f32(&1 + i)),
         Map.update(hot, {key, k}, f32(c * 0.3), &f32(&1 + c * 0.3))}
    end
  end

  defp water?(cells, k), do: elem(elem(cells, k), 0) == @water

  defp add_refl(refl, k, r, g, b, f) do
    Map.update(refl, k, {f32(r), f32(g), f32(b), f32(f)}, fn {r0, g0, b0, f0} ->
      {f32(r0 + r), f32(g0 + g), f32(b0 + b), f32(f0 + f)}
    end)
  end

  # Adds to the reflection's colour, leaving the failing lamp's part alone.
  defp add_rgb(refl, k, r, g, b) do
    Map.update(refl, k, {f32(r), f32(g), f32(b), 0.0}, fn {r0, g0, b0, f0} ->
      {f32(r0 + r), f32(g0 + g), f32(b0 + b), f0}
    end)
  end

  # The ships' lights stretch down the water too.
  defp ship_reflections(refl, cells) do
    for {x, _r0, cr, cg, cb} <- @ship_lights,
        r <- @hz..(@hz + 13),
        dx <- -1..1,
        x + dx < @w,
        k = r * @w + x + dx,
        water?(cells, k),
        reduce: refl do
      refl ->
        a = :math.exp(-(r - @hz) / 5) * 0.35
        g = a * :math.exp(-dx * dx * 2.5)
        add_rgb(refl, k, g * cr, g * cg, g * cb)
    end
  end

  # The mirror: each water cell sees the picture above the shore, flipped and
  # stretched toward us, dimmed.
  defp mirror(refl, cells) do
    for r <- 0..(@h - 1), x <- 0..(@w - 1), water?(cells, r * @w + x), reduce: refl do
      refl ->
        k = r * @w + x
        sy = sea_top(x + 0.5)
        d = r + 0.5 - sy

        # Only the lights carry across: the sky, the towers' lit floors, ships.
        {ar, ag, ab, n} =
          Enum.reduce(0..2, {0, 0, 0, 0}, fn o, {ar, ag, ab, n} = acc ->
            ym = floor(sy - d * 0.55 - 0.3 - o * 0.7)

            case if(ym >= 0, do: elem(cells, ym * @w + x)) do
              nil ->
                acc

              {@water, _, _, _, _, _, _} ->
                acc

              {@sky, cr, cg, cb, _, _, _} ->
                {ar + cr, ag + cg, ab + cb, n + 1}

              {m, cr, cg, cb, _, _, _} when m in [@tower, @ship] ->
                {ar + lit(cr), ag + lit(cg), ab + lit(cb), n + 1}

              _ ->
                {ar, ag, ab, n + 1}
            end
          end)

        a = 0.32 * :math.exp(-d / 30)
        refl = if n != 0, do: add_rgb(refl, k, ar / n * a, ag / n * a, ab / n * a), else: refl

        # And a soft warm sheen off the whole lit shore.
        if x + 0.5 <= @tip + 4 do
          sh = 0.025 * :math.exp(-d / 5) * smooth(@tip + 4, @tip - 6, x + 0.5)
          add_rgb(refl, k, sh, sh * @s1, sh * @s2)
        else
          refl
        end
    end
  end

  defp lit(v), do: max(0, v - 0.25) * 0.6

  # --- clouds ------------------------------------------------------------------

  defp clouds do
    for r <- 0..(@hz - 1) do
      y = r + 0.5

      row =
        for x <- 0..(@cw - 1) do
          d = density(x, y)

          {f32(smooth(0.47, 0.62, d) * 0.9),
           f32(clamp(0.5 + (d - density(x - 1, y + 2.5)) * 9 - (d - 0.6) * 1.4))}
        end

      {row |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
       row |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
    end
    |> List.to_tuple()
  end

  defp density(x, y) do
    q = fbm(x * 0.01, y * 0.05, 3, 8)
    d = fbm(x * 0.025 + q * 2.6, y * 0.07 + q * 1.3, 5, 20)
    # The bank's edge rises and falls.
    yb = y + 14 * (fbm(x * 0.005 + 3, 7, 2, 4) - 0.5)
    d + 0.05 * smooth(2, 14, yb) - 0.1 * smooth(6, 0, y) - 0.1 * smooth(22, @hz - 4, yb)
  end

  # --- init --------------------------------------------------------------------

  @impl true
  def init(_options) do
    table = u_table()
    uend = u_of(table, @tip)
    lamps = lamps(table, uend)
    blds = buildings(uend)
    col_u = List.to_tuple(for x <- 0..(@w - 1), do: f32(u_of(table, x + 0.5)))

    bld_at =
      List.to_tuple(
        for x <- 0..(@w - 1) do
          u = elem(col_u, x)

          if x + 0.5 > @tip,
            do: -1,
            else:
              blds
              |> Enum.with_index()
              |> Enum.reduce(-1, fn {{u0, u1, _, _, _}, i}, at ->
                if u >= u0 and u < u1, do: i, else: at
              end)
        end
      )

    ctx = %{lamps: lamps, blds: List.to_tuple(blds), col_u: col_u, bld_at: bld_at}

    {cells, flicks, beacons} =
      for r <- 0..(@h - 1), x <- 0..(@w - 1), reduce: {[], [], []} do
        {cells, flicks, beacons} ->
          {cell, f, b} = picture(x, r, ctx)
          {[cell | cells], Enum.reverse(f, flicks), Enum.reverse(b, beacons)}
      end

    cells = cells |> Enum.reverse() |> List.to_tuple() |> ships()
    flicks = Enum.reverse(flicks)
    beacons = Enum.reverse(beacons)
    {lit, hot, refl} = lamp_light(lamps, cells)
    cells = lamp_lit(cells, lit, hot)
    refl = refl |> ship_reflections(cells) |> mirror(cells)

    %{
      lut: Palette.nearest_lut(@meta.palette),
      cells: cells,
      flicks: flicks,
      beacons: beacons,
      uend: uend
    }
    |> Map.merge(frame_data(cells, lit, hot, refl, table, uend))
  end

  # The lamps light everything but the sky and the water.
  defp lamp_lit(cells, lit, hot) do
    cells
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.map(fn
      {{m, _, _, _, _, _, _} = cell, _k} when m in [@water, @sky] ->
        cell

      {{m, cr, cg, cb, fl, lane, sky_glow}, k} ->
        li = Map.get(lit, {:lamp, k}, 0.0)
        lw = Map.get(hot, {:lamp, k}, 0.0)

        {m, f32(cr + (li + lw)), f32(cg + (li * @s1 + lw * 0.95)),
         f32(cb + (li * @s2 + lw * 0.8)), fl, lane, sky_glow}
    end)
    |> List.to_tuple()
  end

  defp frame_data(cells, lit, hot, refl, table, uend) do
    nb = ceil((uend + 12) / @bin)

    %{
      rows: rows(cells, lit, hot, refl),
      cover: clouds(),
      nb: nb,
      cars:
        for(
          i <- 0..25,
          do: {Hash.scene(i, 51) * (uend + 12), 4.2 + 1.6 * Hash.scene(i, 52), band(i, 1)}
        ),
      bins:
        List.to_tuple(
          for x <- 0..(@w - 1) do
            lo = max(0, floor((u_of(table, x) - @u0) / @bin))
            {lo, min(nb - 1, max(lo, floor((u_of(table, x + 1) - @u0) / @bin)))}
          end
        ),
      memo: fresh_memo(),
      bounds: pow_bounds(),
      # Tests turn the fast paths off (the memo, the power's bounds, the
      # skipped glint) to check that frames come out the same without them.
      exact?: false
    }
  end

  defp fresh_memo, do: List.duplicate(List.duplicate(:none, @w), @h)

  # Each cell as the frame shades it, row by row.
  defp rows(cells, lit, hot, refl) do
    for r <- 0..(@h - 1) do
      y = r + 0.5

      specs =
        for x <- 0..(@w - 1) do
          k = r * @w + x
          {m, cr, cg, cb, fl, lane, sky_glow} = elem(cells, k)

          flicker =
            case Map.fetch(lit, {:flick, k}) do
              {:ok, f} -> {f, Map.get(hot, {:flick, k}, 0.0)}
              :error -> nil
            end

          case m do
            @water ->
              water_spec(x, y)

            @sky ->
              sky_spec(x, r, y, {cr, cg, cb}, sky_glow, lit, hot, flicker)

            @road ->
              {:road, cr, cg, cb, fl, lane, flicker}

            _ ->
              {:still, cr, cg, cb, fl, flicker}
          end
        end

      {r, row_consts(r, refl), specs}
    end
  end

  defp water_spec(x, y) do
    # The moon's road on the open water.
    road = :math.exp(-sq((x + 0.5 - @moon_x) / (0.8 + (y - @hz) * 0.12)))

    # Its glint adds at most `0.93 * road` to colours of at least 0.015 (the
    # dimmest water: 0.04 * 0.45 * 0.85), whose half-ulp is above 8e-19; so
    # where the road is under 1e-19 the sum is the colour itself, and the
    # glint (its noise too) is skipped.
    glint = if road >= 1.0e-19, do: road_terms(road)
    {:water, 0.85 + 0.3 * (x / @w), road, glint}
  end

  defp road_terms(road), do: {0.03 * road, 0.035 * road, 0.05 * road}

  defp sky_spec(x, r, y, rgb, sky_glow, lit, hot, flicker) do
    k = r * @w + x
    dmx = x + 0.5 - @moon_x
    dmy = y - @moon_y
    dm = :math.sqrt(dmx * dmx + dmy * dmy)
    near = :math.exp(-dm / 16)
    xc = x + 0.5
    clear = f32(1 - 0.9 * smooth(84, 96, xc) * smooth(186, 176, xc) * smooth(20, 28, y))

    star =
      if y < @hz - 14 and Hash.scene(x, r * 3 + 11) > 0.993,
        do: {1.3 + Hash.scene(x, r) * 2.5, Hash.scene(r, x) * 6.28}

    {:sky, rgb, clear, 0.42 + 0.9 * sky_glow + 0.5 * near, smooth(@moon_r, @moon_r + 4, dm), star,
     {Map.get(lit, {:lamp, k}, 0.0), Map.get(hot, {:lamp, k}, 0.0)}, flicker}
  end

  defp row_consts(r, refl) when r + 0.5 >= @hz do
    y = r + 0.5
    v = (y - @hz) / (@h - @hz)

    {0.05 - 0.01 * v, 0.095 - 0.015 * v, 0.23 - 0.03 * v, 1.4 + 4.5 * v,
     smooth(@h + 6, @h - 8, y),
     List.to_tuple(for x <- 0..(@w - 1), do: Map.get(refl, r * @w + x, {0.0, 0.0, 0.0, 0.0}))}
  end

  # Low cloud thins into the haze, so the horizon and the ships stay clear.
  defp row_consts(r, _refl), do: 1 - 0.8 * smooth(27, 37, r + 0.5)

  # --- the frame ---------------------------------------------------------------

  @impl true
  def frame(state, t, env) do
    # The failing lamp.
    lamp_on =
      if :math.sin(t * 0.7) > 0.45,
        do: if(Hash.scene(floor(t * 9), 77) > 0.45, do: 1.0, else: 0.15),
        else: 1.0

    {col_a, col_b} = traffic(state, t)

    fr = %{
      t: t,
      drift: t * 1.3,
      lamp_on: lamp_on,
      col_a: col_a,
      col_b: col_b,
      cover: state.cover,
      color?: env.color?,
      bounds: if(state.exact?, do: nil, else: state.bounds),
      exact?: state.exact?
    }

    waves = waves(t)

    {memo, lut} =
      state.rows
      |> Enum.zip(if state.exact?, do: fresh_memo(), else: state.memo)
      |> Enum.map_reduce(state.lut, fn {{r, consts, specs}, memo}, lut ->
        row(specs, memo, 0, {r, consts, fr, wave(waves, r)}, lut, [])
      end)

    {marks, lut} = rooms_and_beacons(state, t, fr, lut)

    rows =
      memo
      |> Enum.with_index()
      |> Enum.map(fn {cells, r} -> overlaid(cells, 0, Map.get(marks, r)) end)

    text = Enum.map(rows, &chars/1)
    colors = if env.color?, do: rows |> Enum.map(&colours/1) |> IO.iodata_to_binary()
    {Enum.intersperse(text, ?\n), colors, %{state | lut: lut, memo: memo}}
  end

  # Cars: tail lights heading out to the point, headlights coming home; the
  # brightest trail over each column, lane by lane.
  defp traffic(state, t) do
    span = state.uend + 12
    nb = state.nb

    {lane_a, lane_b} =
      Enum.reduce(state.cars, {%{}, %{}}, fn {p0, v, dir}, {lane_a, lane_b} ->
        p = :math.fmod(:math.fmod(p0 + if(dir != 0, do: -v, else: v) * t, span) + span, span)
        head = floor(p / @bin)

        trail =
          for i <- 0..25,
              b = if(dir != 0, do: head + i, else: head - i),
              b >= 0 and b < nb,
              do: {b, :math.exp(-i / 7) * if(i < 2, do: 1.3, else: 0.85)}

        if dir != 0,
          do: {lane_a, light(lane_b, trail)},
          else: {light(lane_a, trail), lane_b}
      end)

    cols =
      for x <- 0..(@w - 1) do
        {lo, hi} = elem(state.bins, x)

        Enum.reduce(lo..hi//1, {0.0, 0.0}, fn i, {a, b} ->
          {max(a, Map.get(lane_a, i, 0.0)), max(b, Map.get(lane_b, i, 0.0))}
        end)
      end

    {cols |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
     cols |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
  end

  defp light(lane, trail) do
    Enum.reduce(trail, lane, fn {b, e}, lane ->
      if e > Map.get(lane, b, 0.0), do: Map.put(lane, b, f32(e)), else: lane
    end)
  end

  # The water's five noises, each sampled on a lattice whose x part depends
  # on the column alone and y part on the row alone: {columns, rows}.
  defp waves(t) do
    {field(0.06, t * 0.1, 0.5, -(t * 0.5)), field(0.18, -(t * 0.2), 1.0, -(t * 1.0)),
     field(0.3, t * 0.3, 1.4, -(t * 1.4)), field(0.05, 7, 0.32, -(t * 0.7)),
     field(0.16, 3, 0.85, -(t * 1.3))}
  end

  # Value noise at (x * ax + bx, y * ay + by) for every column and every row of
  # the water: each column's lattice cell and weight, each row's weight and
  # the hashes along its two lattice rows.
  defp field(ax, bx, ay, by) do
    cols = for x <- 0..(@w - 1), do: lattice_at(x * ax + bx)
    {x_min, x_max} = cols |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    rows = for r <- @hz..(@h - 1), do: lattice_at((r + 0.5) * ay + by)
    {y_min, y_max} = rows |> Enum.map(&elem(&1, 0)) |> Enum.min_max()

    hashes =
      List.to_tuple(
        for yi <- y_min..(y_max + 1) do
          List.to_tuple(for xi <- x_min..(x_max + 1), do: Hash.scene(xi, yi))
        end
      )

    {List.to_tuple(for {xi, u} <- cols, do: {xi - x_min, u}),
     List.to_tuple(
       for {yi, v} <- rows,
           do: {v, elem(hashes, yi - y_min), elem(hashes, yi - y_min + 1)}
     )}
  end

  # A water row's five noises: each one's columns, and this row's weight and hashes.
  defp wave(_noise, r) when r < @hz, do: nil

  defp wave(noise, r) do
    noise
    |> Tuple.to_list()
    |> Enum.map(fn {cols, rows} -> {cols, elem(rows, r - @hz)} end)
    |> List.to_tuple()
  end

  defp lattice_at(p) do
    i = floor(p)
    f = p - i
    {i, f * f * (3 - 2 * f)}
  end

  # `noise(x, y, 0)` from its lattice: the column's cell and weight, the
  # row's weight and the hashes of its two lattice rows.
  defp noise({cols, {v, h0, h1}}, x) do
    {off, u} = elem(cols, x)
    bilerp(elem(h0, off), elem(h0, off + 1), elem(h1, off), elem(h1, off + 1), u, v)
  end

  defp bilerp(a, b, c, d, u, v)
       when is_float(a) and is_float(b) and is_float(c) and is_float(d) and is_float(u) and
              is_float(v),
       do: a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

  defp overlaid(cells, _x, nil), do: cells
  defp overlaid([], _x, _marks), do: []

  defp overlaid([cell | cells], x, marks) do
    case marks do
      %{^x => {char, colour}} -> [{:mark, 0, 0, char, colour} | overlaid(cells, x + 1, marks)]
      _ -> [cell | overlaid(cells, x + 1, marks)]
    end
  end

  defp chars([]), do: []
  defp chars([{_, _, _, char, _} | cells]), do: [char | chars(cells)]

  defp colours([]), do: []
  defp colours([{_, _, _, _, colour} | cells]), do: [colour | colours(cells)]

  # Each cell gives {r, g, b, its dot, its colour}, which the next frame keeps
  # as a memo: a cell shaded to the same colour draws the same dot, and (its
  # colour already in the cache) the same colour.
  defp row([], [], _x, _ctx, lut, acc), do: {Enum.reverse(acc), lut}

  defp row([spec | specs], [memo | memos], x, ctx, lut, acc) do
    {cell, lut} = shade(spec, memo, x, ctx, lut)
    row(specs, memos, x + 1, ctx, lut, [cell | acc])
  end

  defp shade({:still, cr, cg, cb, fl, flicker}, memo, x, {r, _, fr, _}, lut) do
    {cr, cg, cb} = flicker(flicker, cr, cg, cb, fr.lamp_on)
    dot(cr, cg, cb, fl, 1.0, x, r, memo, fr, lut)
  end

  defp shade({:road, cr, cg, cb, fl, lane, flicker}, memo, x, {r, _, fr, _}, lut) do
    a = if band(lane, 1) != 0, do: elem(fr.col_a, x), else: 0.0
    b = if band(lane, 2) != 0, do: elem(fr.col_b, x), else: 0.0
    cr = cr + (a * 0.8 + b * 1.0)
    cg = cg + (a * 0.1 + b * 0.9)
    cb = cb + (a * 0.08 + b * 0.72)
    {cr, cg, cb} = flicker(flicker, cr, cg, cb, fr.lamp_on)
    dot(cr, cg, cb, fl, 1.0, x, r, memo, fr, lut)
  end

  defp shade({:sky, rgb, clear, warmth, off_moon, star, lamp, flicker}, memo, x, ctx, lut) do
    {r, haze, %{drift: drift} = fr, _} = ctx
    {cover, lit} = elem(fr.cover, r)
    sx = x + drift
    ix = floor(sx)
    fx = sx - ix
    i0 = rem(ix, @cw)
    i1 = rem(ix + 1, @cw)
    c = lerp(elem(cover, i0), elem(cover, i1), fx) * clear

    {cr, cg, cb} =
      cond do
        c > 0.01 ->
          cloud(rgb, c, lerp(elem(lit, i0), elem(lit, i1), fx), warmth, off_moon, haze)

        star != nil ->
          {speed, phase} = star
          tw = 0.3 + 0.2 * :math.sin(fr.t * speed + phase)
          {cr, cg, cb} = rgb
          {max(cr, tw * 0.9), max(cg, tw * 0.9), max(cb, tw)}

        true ->
          rgb
      end

    {cr, cg, cb} = lamps(lamp, cr, cg, cb)
    {cr, cg, cb} = flicker(flicker, cr, cg, cb, fr.lamp_on)
    dot(cr, cg, cb, 0.14, 1.0, x, r, memo, fr, lut)
  end

  defp shade({:water, open, road, glint}, memo, x, {r, consts, fr, wave}, lut) do
    {n1, n2, n3, n4, n5} = wave
    {wr, wg, wb, wobble, fade, refl} = consts
    w = 0.6 * noise(n1, x) + 0.4 * noise(n2, x)
    {cr, cg, cb} = sea(w, open, wr, wg, wb)

    # The moon's road on the open water.
    {cr, cg, cb} =
      case glint do
        {rr, rg, rb} -> road(cr, cg, cb, {rr, rg, rb}, w, noise(n3, x), road)
        nil when fr.exact? -> road(cr, cg, cb, road_terms(road), w, noise(n3, x), road)
        nil -> {cr, cg, cb}
      end

    # The reflections, pushed sideways by the swell and broken into dashes.
    sx = (x + (noise(n4, x) - 0.5) * wobble) |> max(0.0) |> min(@w - 1.001)
    ix = trunc(sx)
    dash = 0.45 + 0.9 * smooth(0.2, 0.55, noise(n5, x))
    {rr, rg, rb} = reflect(elem(refl, ix), elem(refl, ix + 1), sx - ix, dash, fr.lamp_on)
    # Where the warm light lies on the water it replaces the blue, so the
    # streaks stay gold instead of mixing to pink.
    {cr, cg, cb} = kill(cr, cg, cb, rr, rg, rb)
    dot(cr, cg, cb, 0.16, fade, x, r, memo, fr, lut)
  end

  defp lerp(a, b, f) when is_float(a) and is_float(b) and is_float(f), do: a + (b - a) * f

  defp sea(w, open, wr, wg, wb)
       when is_float(w) and is_float(open) and is_float(wr) and is_float(wg) and is_float(wb) do
    swell = 0.45 + 0.95 * w
    {wr * swell * open, wg * swell * open, wb * swell * open}
  end

  defp road(cr, cg, cb, {rr, rg, rb}, w, n, road)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(rr) and is_float(rg) and
              is_float(rb) and is_float(w) and is_float(n) and is_float(road) do
    glint = smooth(0.52, 0.8, 0.45 * w + 0.55 * n) * road
    {cr + (0.9 * glint + rr), cg + (0.88 * glint + rg), cb + (0.8 * glint + rb)}
  end

  defp reflect({a0, a1, a2, af}, {b0, b1, b2, bf}, fx, dash, on)
       when is_float(a0) and is_float(a1) and is_float(a2) and is_float(af) and is_float(b0) and
              is_float(b1) and is_float(b2) and is_float(bf) and is_float(fx) and
              is_float(dash) and is_float(on) do
    fl = (af + (bf - af) * fx) * dash * on

    {(a0 + (b0 - a0) * fx) * dash + fl, (a1 + (b1 - a1) * fx) * dash + fl * @s1,
     (a2 + (b2 - a2) * fx) * dash + fl * @s2}
  end

  defp kill(cr, cg, cb, rr, rg, rb)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(rr) and is_float(rg) and
              is_float(rb) do
    kill = 1 - 0.9 * clamp((rr - rb) * 3)
    {cr * kill + rr, cg * kill + rg, cb * kill + rb}
  end

  # Grey-violet, warmed underneath by the city.
  defp cloud({cr, cg, cb}, c, l, warmth, off_moon, haze)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(c) and is_float(l) and
              is_float(warmth) and is_float(off_moon) and is_float(haze) do
    b = clamp(0.1 + l * warmth)

    {kr, kg, kb} =
      if b < 0.5,
        do: {mix(0.05, 0.22, b * 2), mix(0.06, 0.26, b * 2), mix(0.15, 0.44, b * 2)},
        else: {mix(0.22, 0.9, b * 2 - 1), mix(0.26, 0.88, b * 2 - 1), mix(0.44, 0.92, b * 2 - 1)}

    a = min(1.0, c * 1.1) * off_moon * haze
    {mix(cr, kr, a), mix(cg, kg, a), mix(cb, kb, a)}
  end

  # The steady lamps' light on the sky.
  defp lamps({li, lw}, cr, cg, cb)
       when is_float(li) and is_float(lw) and is_float(cr) and is_float(cg) and is_float(cb),
       do: {cr + (li + lw), cg + (li * @s1 + lw * 0.95), cb + (li * @s2 + lw * 0.8)}

  # The failing lamp's light, where it reaches.
  defp flicker(nil, cr, cg, cb, _on), do: {cr, cg, cb}

  defp flicker({fi, fw}, cr, cg, cb, on) do
    f = fi * on
    fw = fw * on
    {cr + (f + fw), cg + (f * @s1 + fw * 0.95), cb + (f * @s2 + fw * 0.8)}
  end

  # Dot size from brightness, dithered; the colour makes up what the dot size
  # could not. A memo of the same colour already has both.
  defp dot(cr, cg, cb, fl, fade, x, r, memo, fr, lut)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(fl) and is_float(fade) do
    color? = fr.color?

    case memo do
      {^cr, ^cg, ^cb, _char, colour} when colour != nil or not color? ->
        {memo, lut}

      _ ->
        peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
        bayer = elem(@bayer, band(r, 3) * 4 + band(x, 3))
        {step, want} = settle(peak, fl, fade, bayer, color?, fr.bounds)

        if color? do
          s = (0.3 + 0.7 * want) / peak
          {i, lut} = Palette.nearest(lut, clamp(cr * s), clamp(cg * s), clamp(cb * s))
          {{cr, cg, cb, elem(@dots, step), i}, lut}
        else
          {{cr, cg, cb, elem(@dots, step), nil}, lut}
        end
    end
  end

  defp level(p, fl, fade) when is_float(p) and is_float(fl) and is_float(fade),
    do: clamp(fl + (1 - fl) * p * 0.95) * fade

  defp step(level, bayer) when is_float(level) and is_float(bayer),
    do: max(0, min(3, js_round(level * 3 + bayer)))

  defp want(0, _level), do: 0.0
  defp want(step, level) when is_float(level), do: min(1.0, (level + 0.06) / elem(@cover, step))

  # The dot's step and the weight of its colour. Both rise with
  # `Math.pow(peak, 0.85)`, so where they are the same at both ends of that
  # power's bounds (and the weight is 0 or full) they need not wait for it.
  defp settle(peak, fl, fade, bayer, color?, bounds) when is_tuple(bounds) and peak < @pow_top do
    {lo, hi} = elem(bounds, trunc(peak * @grain))
    low = level(lo, fl, fade)
    step = step(low, bayer)

    cond do
      step != step(level(hi, fl, fade), bayer) -> exact(peak, fl, fade, bayer)
      step == 0 -> {0, 0.0}
      not color? -> {step, nil}
      want(step, low) == 1 -> {step, 1.0}
      true -> exact(peak, fl, fade, bayer)
    end
  end

  defp settle(peak, fl, fade, bayer, _color?, _bounds), do: exact(peak, fl, fade, bayer)

  defp exact(peak, fl, fade, bayer) do
    level = level(:math.pow(peak, 0.85), fl, fade)
    step = step(level, bayer)
    {step, want(step, level)}
  end

  # Bounds on `Math.pow(peak, 0.85)` for a peak in [i, i + 1) / GRAIN: each
  # end's power, widened by far more than the error of a libm's pow (under an
  # ulp), so the true power of any peak inside lies between them.
  defp pow_bounds do
    List.to_tuple(
      for i <- 0..(@pow_top * @grain - 1) do
        {:math.pow(i / @grain, 0.85) * (1 - 1.0e-12),
         :math.pow((i + 1) / @grain, 0.85) * (1 + 1.0e-12)}
      end
    )
  end

  # Rooms whose light changes, and the aviation lights, painted over the
  # shading in turn.
  defp rooms_and_beacons(state, t, fr, lut) do
    rooms =
      Enum.map(state.flicks, fn {k, wr, wg, wb, kind, rate, ph} ->
        {_, sr, sg, sb, _, _, _} = elem(state.cells, k)

        if kind != 0 do
          # A television: cold light that jumps.
          f = 0.5 + 0.5 * :math.sin(t * 11 + ph) * :math.sin(t * 4.3 + ph * 2)
          {k, sr - wr + f * wr * 0.45, sg - wg + f * wr * 0.6, sb - wb + f * wr, 0.08}
        else
          # A light switched off for a while, then on again.
          f = if :math.sin(t * rate * 0.5 + ph) > -0.6, do: 1, else: 0
          {k, sr - wr * (1 - f), sg - wg * (1 - f), sb - wb * (1 - f), 0.08}
        end
      end)

    beacons =
      for {k, ph} <- state.beacons, k >= 0 do
        if :math.sin(t * 2.4 + ph) > 0.3,
          do: {k, 1.0, 0.2, 0.15, 0.1},
          else: {k, 0.3, 0.06, 0.05, 0.1}
      end

    Enum.reduce(rooms ++ beacons, {%{}, lut}, fn {k, cr, cg, cb, fl}, {marks, lut} ->
      {{_, _, _, char, colour}, lut} =
        dot(
          max(0.0, cr),
          max(0.0, cg),
          max(0.0, cb),
          fl,
          1.0,
          rem(k, @w),
          div(k, @w),
          :none,
          fr,
          lut
        )

      {Map.update(
         marks,
         div(k, @w),
         %{rem(k, @w) => {char, colour}},
         &Map.put(&1, rem(k, @w), {char, colour})
       ), lut}
    end)
  end
end
