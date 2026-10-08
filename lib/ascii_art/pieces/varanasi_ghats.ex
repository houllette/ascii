defmodule AsciiArt.Pieces.VaranasiGhats do
  @moduledoc """
  Dusk aarti on the ganga, lamps on the steps and diyas on the water.

  Dusk on the ganga. Stepped ghats run along the bank and away toward the
  afterglow, temple spires black against an indigo to amber sky. Priests
  raise the aarti lamps on the steps, diyas drift downstream on the dark
  water, and a boatman rows slowly across the bright reach.

  Shaded in colour cell by cell, then drawn as a halftone: a dot whose size
  is the cell's brightness, ordered-dithered, in the palette colour nearest
  its hue.

  Ported from `src/pieces/varanasi-ghats.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Hash, Palette}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "varanasi ghats",
    category: :scenes,
    note: "dusk aarti on the ganga, lamps on the steps and diyas on the water",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#0b0812",
    palette: [
      # the sky, indigo through violet
      "#141230",
      "#1d1a42",
      "#272257",
      "#332b6a",
      "#45357a",
      "#5a4388",
      "#7259a8",
      # plum, orchid, mauve and rose
      "#6d3a73",
      "#8a4677",
      "#a8527a",
      "#c4607a",
      "#d97a92",
      "#b866a0",
      "#9a68c8",
      "#c868b0",
      "#e8707a",
      # coral to gold
      "#d9705f",
      "#e88552",
      "#f29f4a",
      "#f8b85a",
      "#fcd07a",
      "#ffe3a6",
      "#fff2d2",
      # stone in shadow, and the violet treads
      "#1a1220",
      "#24182a",
      "#301f33",
      "#3f2838",
      "#523340",
      "#3a2c4c",
      "#4d3a64",
      # stone in lamplight
      "#5e3524",
      "#7d4527",
      "#a0582a",
      "#c06e2e",
      "#d98a46",
      # flame
      "#ffffff",
      "#fff6d8",
      "#ffd860",
      "#ff9f2a",
      "#f06a1e",
      "#c8401a",
      "#8a2a16",
      # dark water
      "#0f1a2c",
      "#162540",
      "#20325a",
      # starlight, set directly and never matched
      "#d6d4ee"
    ]
  }

  @w 200
  @h 100
  # The far bank.
  @hz 60
  # Where the ghats meet the far bank.
  @end_x 150
  # The afterglow, sitting on the far bank.
  @glow_x 156
  @glow_y @hz - 1.5
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  # How far a dot's colour may be brightened to make up for its size: small
  # dots in dark areas stay dark instead of turning into a pale speckle.
  @lift {0, 2.5, 1.7, 1.35}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()
  # The flame's colour and the lamps' wash on the stone, past their red,
  # which is 1 (upstream multiplies by it; here it is left out).
  @flame_g 0.62
  @flame_b 0.22
  @wash_g 0.5
  @wash_b 0.2
  # The starlight colour, the palette's last.
  @star 45

  @sky 0
  @water 1
  @bank 2
  @steps 3
  @bld 4
  @spire 5
  @umb 6
  @fig 7
  @plat 8

  # Heat, then colour: indigo overhead, violet, plum, rose, coral, amber,
  # gold.
  @ramp {
    {0.0, 0.085, 0.07, 0.24},
    {0.14, 0.13, 0.1, 0.34},
    {0.28, 0.22, 0.14, 0.44},
    {0.42, 0.34, 0.17, 0.48},
    {0.52, 0.47, 0.21, 0.47},
    {0.62, 0.6, 0.26, 0.42},
    {0.7, 0.7, 0.31, 0.36},
    {0.78, 0.8, 0.39, 0.3},
    {0.86, 0.88, 0.5, 0.26},
    {0.92, 0.95, 0.65, 0.32},
    {0.97, 1.0, 0.8, 0.48},
    {1.0, 1.0, 0.92, 0.7}
  }
  @rl 256

  # Temple spires: {centre x, height in rows, half width at the base}.
  @spires [{118, 33, 5.2}, {64, 19, 4}, {31, 15, 3.6}, {139, 8, 1.6}, {90, 11, 2.4}, {129, 10, 2}]
  # Aarti stations on the near ghat, unevenly spaced: {x, streak width,
  # streak length}.
  @aarti [{11, 1.15, 1.25}, {24, 0.8, 0.85}, {39, 1.25, 1.1}, {54, 0.75, 0.75}]
  # Umbrellas on the far steps.
  @umbs [70, 83, 98, 109]
  # The clouds' strip, which wraps, and its height.
  @cw 800
  @ch @hz - 6
  # The boat's scale.
  @bs 0.85

  @impl true
  def meta, do: @meta

  @compile {:inline,
            clamp: 1,
            smooth: 3,
            mix: 3,
            fround: 1,
            noise: 2,
            lattice: 4,
            imul_x: 1,
            imul_y: 1,
            mix_hash: 1,
            cube: 1,
            dyn_at: 3,
            refl_at: 4,
            warm_at: 4,
            road_at: 4,
            add: 4}
  defp clamp(v) when v < 0, do: 0
  defp clamp(v) when v > 1, do: 1
  defp clamp(v), do: v

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  # `JSMath.fround/1`, here so that it inlines.
  defp fround(x) do
    <<f::float-32>> = <<x::float-32>>
    f
  end

  # `AsciiArt.Kit.Scene.noise/3` and `fbm/4`, for the integer periods used
  # here, and in them the scenes' hash (`AsciiArt.Kit.Hash.scene/2`) of the
  # four lattice points, written out so that the products shared between
  # them are made once and all of it inlines: `imul` in unsigned arithmetic,
  # wrapped modulo 2^32 where JS wraps.
  defp noise(x, y) do
    xi = floor(x)
    lattice(x, y, xi, xi + 1)
  end

  defp noise(x, y, 0), do: noise(x, y)

  defp noise(x, y, period) do
    x0 = Integer.mod(floor(x), period)
    lattice(x, y, x0, rem(x0 + 1, period))
  end

  defp lattice(x, y, x0, x1) do
    yi = floor(y)
    fx = x - floor(x)
    fy = y - yi
    u = fx * fx * (3 - 2 * fx)
    v = fy * fy * (3 - 2 * fy)
    x0 = imul_x(x0)
    x1 = imul_x(x1)
    y0 = imul_y(yi)
    y1 = imul_y(yi + 1)
    a = mix_hash(x0 + y0)
    b = mix_hash(x1 + y0)
    c = mix_hash(x0 + y1)
    d = mix_hash(x1 + y1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  defp fbm(x, y, octaves, period), do: fbm(x, y, octaves, period, 0, 0, 0.5, 1)

  defp fbm(_x, _y, 0, _period, s, n, _amp, _f), do: s / n

  defp fbm(x, y, octaves, period, s, n, amp, f),
    do:
      fbm(
        x,
        y,
        octaves - 1,
        period,
        s + amp * noise(x * f, y * f, period * f),
        n + amp,
        amp * 0.5,
        f * 2
      )

  @hx 374_761_393
  @hy 668_265_263
  @hm 1_274_126_177

  # Math.imul(i, 374761393) and Math.imul(i, 668265263), not yet wrapped.
  defp imul_x(i) do
    i = band(i, 0xFFFFFFFF)
    band(i, 0xFFFF) * @hx + bsl(band(bsr(i, 16) * band(@hx, 0xFFFF), 0xFFFF), 16)
  end

  defp imul_y(i) do
    i = band(i, 0xFFFFFFFF)
    band(i, 0xFFFF) * @hy + bsl(band(bsr(i, 16) * band(@hy, 0xFFFF), 0xFFFF), 16)
  end

  defp mix_hash(h) do
    h = band(h, 0xFFFFFFFF)
    g = bxor(h, bsr(h, 13))

    h =
      band(
        band(g, 0xFFFF) * @hm + bsl(band(bsr(g, 16) * band(@hm, 0xFFFF), 0xFFFF), 16),
        0xFFFFFFFF
      )

    bxor(h, bsr(h, 16)) / 4_294_967_296
  end

  defp hash(x, y), do: Hash.scene(x, y)

  # The heat ramp, tabulated, as Float32 {r, g, b} by step.
  @ramp_table List.to_tuple(
                for i <- 0..256 do
                  h = i / 256

                  j =
                    Enum.find(0..9, 10, fn j ->
                      not (h > elem(elem(@ramp, j + 1), 0))
                    end)

                  {h0, r0, g0, b0} = elem(@ramp, j)
                  {h1, r1, g1, b1} = elem(@ramp, j + 1)
                  k = min(1, max(0, (h - h0) / (h1 - h0)))

                  for v <- [r0 + (r1 - r0) * k, g0 + (g1 - g0) * k, b0 + (b1 - b0) * k] do
                    <<f::float-32>> = <<v::float-32>>
                    f
                  end
                  |> List.to_tuple()
                end
              )

  defp ramp(h), do: elem(@ramp_table, ramp_at(h))
  defp ramp_at(h), do: trunc(clamp(h) * @rl + 0.5)

  # The waterline along the ghats, near at the left and running away to the
  # right; the ghats' scale there; and the top of their steps.
  defp wl_f(x) when x < @end_x, do: @hz + 0.5 + 20 * :math.pow(1 - x / @end_x, 1.6)
  defp wl_f(_x), do: @hz + 0.5
  defp sc_f(x), do: 0.45 + 1.75 * :math.pow(max(0, 1 - x / @end_x), 1.3)

  defp step_top_f(x),
    do: wl_f(x) - 9.5 * sc_f(x) * (0.3 + 0.7 * smooth(@end_x, @end_x - 16, x))

  # The dusk sky's heat: low overhead, rising toward the horizon, hottest at
  # the glow: a wide warm band along the horizon, and a small hot core on
  # the bank.
  defp sky_heat(x, y) do
    v = clamp(y / @hz)
    dx = abs(x - @glow_x)
    dy = abs(@glow_y - y)
    wide = 0.46 * :math.exp(-dx / 55 - dy / 23)
    a = dx / 13
    b = dy / 4.5
    core = 0.24 * :math.exp(-:math.sqrt(a * a + b * b))
    0.06 + 0.42 * v * v + wide + core
  end

  # --- the bank --------------------------------------------------------------

  # Buildings along the ghats: {x0, x1, height above the steps in scale
  # units, seed}.
  defp blds(x) when x < @end_x - 10 do
    s = sc_f(max(0, x))
    w = (8 + 10 * hash(x, 3)) * s
    low = if(x > 110, do: 0.8, else: 1) * (0.45 + 0.55 * smooth(@end_x - 8, @end_x - 34, x))
    [{x, x + w, (7 + 9 * hash(x, 4)) * low, hash(x, 5)} | blds(x + w)]
  end

  defp blds(_x), do: []

  defp roof_of(x, blds) do
    case Enum.find(blds, fn {x0, x1, _h, _seed} -> x >= x0 and x < x1 end) do
      {_x0, _x1, h, _seed} -> step_top_f(x) - h * sc_f(x)
      nil -> step_top_f(x)
    end
  end

  # Every cell as {material, r, g, b, floor, albedo, warmth}, the floats as
  # upstream's Float32Arrays hold them; albedo is how much the lamps' wash
  # lights each cell.
  defp base_cells(blds) do
    spires = for {sx, sh, sw} <- @spires, do: {sx, sh, sw, roof_of(sx, blds) + 1}

    for r <- 0..(@h - 1), x <- 0..(@w - 1), into: %{} do
      xc = x + 0.5
      y = r + 0.5
      wl = wl_f(xc)

      cell =
        if y >= wl,
          do: {@water, 0, 0, 0, 0, fround(0.25), 0},
          else: land_cell(x, r, xc, y, wl, blds, spires)

      {{r, x}, cell}
    end
  end

  defp land_cell(x, r, xc, y, wl, blds, spires) do
    s = sc_f(xc)
    # The far bank: an embankment and clumps of trees against the glow.
    clump = smooth(0.42, 0.72, fbm(xc * 0.11, 3, 3, 0)) * smooth(160, 172, xc)
    bank_top = @hz - 2.2 - 0.6 * fbm(xc * 0.4, 7, 2, 0) - 4 * clump

    cell =
      if xc >= @end_x - 4 and y >= bank_top,
        do: {@bank, 0.1, 0.07, 0.125, 0.03, 0},
        else: {@sky, 0, 0, 0, 0.06, 0}

    cell = if xc < @end_x, do: ghat(xc, y, wl, s, blds, cell), else: cell
    cell = Enum.reduce(spires, cell, &spire(&1, xc, y, &2))
    cell = Enum.reduce(@umbs, cell, &umbrella(&1, xc, y, &2))
    {m, cr, cg, cb, fl, al} = Enum.reduce(@aarti, cell, &priest(&1, xc, y, &2))

    if m == @sky do
      veil = 0.92 + 0.16 * fbm(x * 0.05, r * 0.1, 3, 0)

      hh =
        sky_heat(xc, y) + 0.05 * (fbm(x * 0.07 + 11, r * 0.16, 2, 0) - 0.5) +
          0.1 * (fbm(x * 0.025 + 3, r * 0.09 + 5, 3, 0) - 0.5)

      {tr, tg, tb} = ramp(hh)

      {@sky, fround(tr * veil), fround(tg * veil), fround(tb * veil), fround(0.2), fround(0),
       fround(smooth(0.3, 0.9, hh))}
    else
      {m, fround(cr), fround(cg), fround(cb), fround(fl), fround(al), 0}
    end
  end

  # The ghats: buildings and their rooftop pavilions, then the steps.
  defp ghat(xc, y, wl, s, blds, cell) do
    st = step_top_f(xc)
    # The last building over this column, if any.
    {roof, bi} =
      blds
      |> Enum.with_index()
      |> Enum.reduce({st, nil}, fn {{x0, x1, h, _}, i}, acc ->
        if xc >= x0 and xc < x1, do: {st - h * s, i}, else: acc
      end)

    top = if bi == nil, do: roof, else: pavilion(xc, s, roof, Enum.at(blds, bi))
    cell = if y >= top and y < st, do: building(xc, y, s, st, top, bi, blds), else: cell
    if y >= st, do: steps(y, wl, s, st), else: cell
  end

  defp pavilion(xc, s, roof, {x0, x1, _h, hb}) do
    mid = (x0 + x1) / 2
    half = (x1 - x0) / 2

    top =
      if hb > 0.45 do
        # A chhatri: a small dome on four posts.
        cx = if hb > 0.75, do: x0 + half * 0.4, else: mid
        dx = abs(xc - cx) / (1.6 * s)

        top =
          if dx < 1, do: min(roof, roof - 1.4 * s - 1.5 * s * :math.sqrt(1 - dx * dx)), else: roof

        if dx < 1.1 and dx > 0.7, do: min(top, roof - 1.4 * s), else: top
      else
        roof
      end

    # Parapet ends.
    if abs(xc - x0) < 0.6 * s or abs(xc - x1) < 0.6 * s, do: min(top, roof - 0.6 * s), else: top
  end

  # Backlit stone, a little violet from the sky, darker low down, with rows
  # of arched openings, a fair number lit on the near ghats.
  defp building(xc, y, s, st, top, bi, blds) do
    fy = (y - top) / max(1, st - top)
    {cr, cg, cb} = {0.075 * (1.1 - 0.4 * fy), 0.05 * (1.1 - 0.4 * fy), 0.09 * (1.1 - 0.3 * fy)}

    {cr, cg, cb, al} =
      with true <- bi != nil and s > 0.6,
           {x0, _x1, h, _} = Enum.at(blds, bi),
           fx = (xc - x0) / (2.4 * s),
           fz = (st - y) / (3 * s),
           ix = floor(fx),
           iz = floor(fz),
           true <-
             fx - ix > 0.35 and fx - ix < 0.7 and fz - iz > 0.25 and fz - iz < 0.75 and iz >= 1 and
               st - y < h * s - 1.5 * s do
        if hash(bi * 31 + ix, iz * 7) < if(s > 1.2, do: 0.28, else: 0.2),
          do: {cr + 0.5, cg + 0.28, cb + 0.08, 0.5},
          else: {cr * 0.55, cg * 0.55, cb * 0.65, 0.2}
      else
        false -> {cr, cg, cb, 0.5}
      end

    {@bld, cr, cg, cb, 0.14, al}
  end

  # The steps: treads catch the violet sky, risers fall in shadow.
  defp steps(y, wl, s, st) do
    sp = 1.6 * s
    near = (wl - y) / (wl - st)

    {cr, cg, cb, al} =
      if sp < 2.2 do
        # Too far to count the steps: a faint alternating tread.
        if band(floor(wl - y), 1) == 1,
          do: {0.19 * 0.55, 0.13 * 0.55, 0.25 * 0.58, 0.4},
          else: {0.19, 0.13, 0.25, 0.75}
      else
        if JSMath.mod((wl - y) / sp, 1) < 0.6,
          do: {0.24 + 0.05 * (1 - near), 0.15, 0.2, 1},
          else: {0.05, 0.035, 0.06, 0.3}
      end

    # The wet bottom steps darker.
    if wl - y < 1.2 * s,
      do: {@steps, cr * 0.6, cg * 0.6, cb * 0.75, 0.12, al * 0.6},
      else: {@steps, cr, cg, cb, 0.12, al}
  end

  # The curved shikhara, an amalaka disc and the kalash on top.
  defp spire({sx, sh, sw, base}, xc, y, cell) do
    h = base - y

    if h < -1 or h > sh + 2.5 do
      cell
    else
      hw = spire_width(h, sh, sw)

      if abs(xc - sx) <= hw do
        band = if rem(floor(h / 1.6), 2) != 0, do: 0.8, else: 1
        {@spire, 0.085 * band, 0.055 * band, 0.095 * band, 0.12, 0.35}
      else
        cell
      end
    end
  end

  # (Below its foot the width is the foot's, which upstream reaches after a
  # power of a negative: it never shows.)
  defp spire_width(h, _sh, sw) when h >= -1 and h < 0.5, do: sw * 1.15

  defp spire_width(h, sh, sw) do
    f = h / sh
    hw = if f <= 1, do: sw * :math.pow(max(0, 1 - :math.pow(f, 1.8)), 0.6), else: 0
    hw = if f > 0.92 and f < 1.02, do: max(hw, sw * 0.32), else: hw

    if f >= 1.02 and h < sh + 2.2,
      do: max(hw, 0.35 + 0.2 * :math.sin((h - sh) / 2.2 * :math.pi())),
      else: hw
  end

  # The big umbrellas on the far steps.
  defp umbrella(ux, xc, y, {m, cr, cg, cb, fl, al}) do
    s2 = sc_f(ux)
    wl2 = wl_f(ux)
    cy = wl2 - (wl2 - step_top_f(ux)) * 0.55
    dx = (xc - ux) / (3 * s2)
    dy = (cy - y) / (1.4 * s2)

    cell =
      if dy > 0 and dy < 1 and abs(dx) < :math.sqrt(1 - dy * dy),
        do: {@umb, 0.07, 0.045, 0.075, fl, 0.4},
        else: {m, cr, cg, cb, fl, al}

    cell =
      if dy <= 0 and dy > -0.25 and abs(dx) < 1,
        do: {@umb, 0.05, 0.03, 0.05, fl, 0.2},
        else: cell

    if abs(xc - ux) < 0.5 and y > cy and y < cy + 2.2 * s2,
      do: {@umb, 0.04, 0.03, 0.04, fl, 0.1},
      else: cell
  end

  # The priests on their platforms, dark against the lit steps: a dhoti, a
  # broad-shouldered torso, a neck and the head.
  defp priest({ax, _sw, _sl}, xc, y, cell) do
    s2 = sc_f(ax)
    u = 1.3 * s2
    base = wl_f(ax) - 2.6 * s2
    dx = (xc - ax) / u
    fy = (base - y) / u

    bw =
      cond do
        fy < 0 -> -1
        fy < 2.2 -> 0.66 - 0.04 * fy
        fy < 4.1 -> 0.58 + 0.32 * smooth(2.2, 3.7, fy)
        fy < 4.5 -> 0.28
        true -> -1
      end

    head = JSMath.hypot(dx * 1.05, fy - 5.05) < 0.62
    cell = if abs(dx) < bw or head, do: {@fig, 0.035, 0.022, 0.035, 0.02, 0.04}, else: cell

    if y >= base and y < base + 0.7 * s2 and abs(xc - ax) < 2.3 * u,
      do: {@plat, 0.12, 0.07, 0.06, 0.04, 0.8},
      else: cell
  end

  # --- light on the bank, built once ---------------------------------------

  defp mat(cells, r, x), do: cells |> Map.fetch!({r, x}) |> elem(0)

  # Rim light: silhouette edges facing the glow take its orange light, and
  # their tops the sky's colour.
  defp rim(cells) do
    rims =
      for r <- 1..(@h - 2),
          x <- 2..(@w - 3),
          m = mat(cells, r, x),
          m != @sky and m != @water,
          into: %{} do
        toward = if x < @glow_x, do: 1, else: -1
        strong = 0.75 * :math.exp(-abs(x - @glow_x) / 42)

        a =
          cond do
            mat(cells, r, x + toward) == @sky -> strong
            mat(cells, r, x + 2 * toward) == @sky -> strong * 0.4
            true -> 0
          end

        rim =
          if a > 0, do: {fround(0.85 * a), fround(0.45 * a), fround(0.26 * a)}, else: {0, 0, 0}

        rim =
          case Map.fetch!(cells, {r - 1, x}) do
            {@sky, ur, ug, ub, _, _, _} ->
              {rr, rg, rb} = rim
              {fround(rr + ur * 0.3), fround(rg + ug * 0.3), fround(rb + ub * 0.3)}

            _ ->
              rim
          end

        {{r, x}, rim}
      end

    Map.new(cells, fn {key, {m, cr, cg, cb, fl, al, warm} = cell} ->
      case rims do
        %{^key => {rr, rg, rb}} ->
          {key, {m, fround(cr + rr), fround(cg + rg), fround(cb + rb), fl, al, warm}}

        _ ->
          {key, cell}
      end
    end)
  end

  # Small diyas lining the steps near the aarti, twinkling: {row, column,
  # phase}.
  defp step_lamps(cells) do
    for x <- 2..117,
        s = sc_f(x + 0.5),
        wl = wl_f(x + 0.5),
        r <- floor(step_top_f(x + 0.5))..(ceil(wl - 1) - 1)//1,
        r < wl - 1,
        mat(cells, r, x) == @steps,
        q = (x - 33) / 36,
        near = :math.exp(-(q * q)),
        hash(x * 3 + 7, r * 5) < 0.035 * near + 0.006,
        JSMath.mod((wl - r - 0.5) / (1.6 * s), 1) < 0.3,
        do: {r, x, hash(x, r) * 40}
  end

  # Electric lamps along the far ghats, each lighting the stone round it
  # and with its thin road on the water: the cells, lit, and the roads.
  defp electric(cells) do
    lamp_xs(58)
    |> Enum.reduce({cells, %{}}, fn x, {cells, roads} ->
      s = sc_f(x)
      st = step_top_f(x)
      h = hash(x, 78)
      ly = st - 0.4 * s + (wl_f(x) - st) * 0.55 * (h * h)
      halo = 1 + 3.2 * s
      reach = ceil(halo * 3)

      cells =
        for r <- max(0, floor(ly - reach))..min(@h - 1, ceil(ly + reach) - 1)//1,
            xx <- max(0, floor(x - reach))..min(@w - 1, ceil(x + reach) - 1)//1,
            reduce: cells do
          cells -> lamp(cells, r, xx, x, ly, halo)
        end

      {cells, road(roads, x, wl_f(x), 0.35 + 0.35 * s, 9 * s)}
    end)
  end

  defp lamp_xs(x) when x < @end_x - 3,
    do: [x | lamp_xs(x + (5 + 10 * hash(x, 77)) * max(0.8, sc_f(x)))]

  defp lamp_xs(_x), do: []

  # The lamp, and the pool of light it throws on the stone round it.
  defp lamp(cells, r, xx, x, ly, halo) do
    case Map.fetch!(cells, {r, xx}) do
      {m, _, _, _, _, _, _} when m in [@water, @sky] ->
        cells

      {m, cr, cg, cb, fl, al, warm} ->
        dx = xx + 0.5 - x
        dy = r + 0.5 - ly
        d = :math.sqrt(dx * dx + dy * dy)
        q = d / 0.6
        v = :math.exp(-(q * q)) * 1.3 + :math.exp(-d / 1.4) * 0.12
        p = :math.exp(-d / halo) * 0.3 * al

        Map.put(
          cells,
          {r, xx},
          {m, fround(cr + (v + p)), fround(cg + (v * 0.76 + p * @wash_g)),
           fround(cb + (v * 0.42 + p * @wash_b)), fl, al, warm}
        )
    end
  end

  defp road(roads, x, wl, width, len) do
    Enum.reduce_while(floor(wl)..(@h - 1)//1, roads, fn r, roads ->
      a = :math.exp(-(r + 0.5 - wl) / len) * 0.5

      if a < 0.01 do
        {:halt, roads}
      else
        roads =
          for xx <- floor(x - 3)..(ceil(x + 3) - 1)//1, reduce: roads do
            roads ->
              q = (xx + 0.5 - x) / width

              Map.update(
                roads,
                {r, xx},
                fround(a * :math.exp(-(q * q))),
                &fround(&1 + a * :math.exp(-(q * q)))
              )
          end

        {:cont, roads}
      end
    end)
  end

  # The reflection: the bank and sky mirrored at the waterline. For each
  # water cell, the colour it mirrors and the lit cell it mirrors (or nil).
  defp reflection(cells) do
    for r <- 0..(@h - 1),
        x <- 0..(@w - 1),
        mat(cells, r, x) == @water,
        into: %{} do
      wl = wl_f(x + 0.5)
      d = r + 0.5 - wl

      {{ar, ag, ab}, mirror} =
        Enum.reduce(0..1, {{0, 0, 0}, nil}, fn o, {{ar, ag, ab}, mirror} ->
          ym = wl - d * 0.85 - 0.4 - o * 0.8
          q = if ym < 0, do: nil, else: {floor(ym), x}
          # The rippled water stretches the sky's light down toward us.
          {tr, tg, tb} = ramp(sky_heat(x + 0.5, max(0, wl - d * 0.36 - 1 - o * 0.6)))

          case q && Map.fetch!(cells, q) do
            {m, cr, cg, cb, _, _, _} when m not in [@water, @sky] ->
              # Tilted ripples under the bank still catch a little sky.
              {{ar + (cr + tr * 0.22), ag + (cg + tg * 0.22), ab + (cb + tb * 0.22)},
               if(o == 0, do: q, else: mirror)}

            _ ->
              {{ar + tr, ag + tg, ab + tb}, mirror}
          end
        end)

      a = 0.8 - 0.4 * smooth(@hz, @h, r)
      {{r, x}, {fround(ar / 2 * a), fround(ag / 2 * a), fround(ab / 2 * a), mirror}}
    end
  end

  # --- clouds: long dusk streaks, dark on top and lit from below -----------

  # Stretched, warped noise, gathered into three loose bands, and one thin,
  # broken streak low down, to cross the glow; `col` holds what depends on
  # x alone.
  defp density(x, y, {c, th, broken}) do
    q = fbm(x * 0.005, y * 0.03, 3, 4)
    d = fbm(x * 0.0125 + q * 1.8, y * 0.09 + q * 0.9, 5, 10)
    a = (y - 13) / 4
    b = (y - 29) / 5.5
    env = 0.03 * :math.exp(-(a * a)) + 0.1 * :math.exp(-(b * b))
    e = (y - c) / th
    streak = :math.exp(-(e * e)) * broken * (0.75 + 0.5 * fbm(x * 0.05, y * 0.3, 3, 40))
    max(d + env - 0.08, 0.36 + 0.3 * streak)
  end

  defp column(x) do
    {46.5 + 3 * (fbm(x * 0.01, 9.5, 2, 8) - 0.5), 1 + 0.9 * fbm(x * 0.05, 3.5, 2, 40),
     smooth(0.42, 0.6, fbm(x * 0.0125, 21.5, 3, 10))}
  end

  defp clouds do
    cols = List.to_tuple(for x <- 0..(@cw - 1), do: column(x))
    # The density on every row's centre line, two rows past the last, as the
    # light below a cell is the density two rows down.
    dens =
      List.to_tuple(
        for r <- 0..(@ch + 1) do
          List.to_tuple(for x <- 0..(@cw - 1), do: density(x, r + 0.5, elem(cols, x)))
        end
      )

    rows =
      for r <- 0..(@ch - 1) do
        y = r + 0.5

        row =
          for x <- 0..(@cw - 1) do
            d = dens |> elem(r) |> elem(x)
            below = dens |> elem(r + 2) |> elem(x)
            # The undersides catch the light from below the horizon, the
            # tops go dark.
            lit =
              clamp(0.4 + (d - below) * 5.5 + (density(x, y - 2.5, elem(cols, x)) - d) * 1.5)

            {fround(smooth(0.47, 0.62, d)), fround(lit)}
          end

        {row |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
         row |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
      end

    {rows |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
     rows |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
  end

  # --- the boat ------------------------------------------------------------

  # The boat crossing the bright reach, in local coordinates: lx along the
  # boat, ly up from the waterline. Its hull's sheer is a cube.
  defp boat?(lx, ly) do
    cond do
      abs(lx) < 9 and ly > -0.6 and ly < 1.2 + 1.4 * :math.pow(abs(lx) / 9, 3) -> true
      # The boatman.
      lx > 4.6 and lx < 5.8 and ly > 0 and ly < 6.6 -> true
      abs(lx - 5.2) < 0.7 and abs(ly - 7.2) < 0.7 -> true
      # His oar, raked back into the water.
      oar?(lx - 5.6, ly - 5.4) -> true
      # A passenger.
      lx > -4 and lx < -0.5 and ly > 0 and ly < 2.6 - 0.25 * abs(lx + 2.2) -> true
      true -> false
    end
  end

  defp oar?(ox, oy) do
    along = ox * 0.42 - oy * 0.91
    along > 0 and along < 8 and abs(ox * 0.91 + oy * 0.42) < 0.32
  end

  # --- init ----------------------------------------------------------------

  @impl true
  def init(_options) do
    blds = blds(-6)
    cells = blds |> base_cells() |> rim()
    lamps = step_lamps(cells)
    {cells, roads} = electric(cells)
    refl = reflection(cells)
    {cover, lit} = clouds()

    # The floating diyas: {x, y, phase, size}.
    diyas =
      for i <- 0..33 do
        y = @hz + 5 + 34 * :math.pow(hash(i, 61), 1.3)
        {hash(i, 62) * 260 - 30, y, hash(i, 63) * 50, 0.6 + 0.6 * hash(i, 64)}
      end

    %{
      cells:
        List.to_tuple(
          for r <- 0..(@h - 1) do
            List.to_tuple(for x <- 0..(@w - 1), do: cell(x, r, cells[{r, x}], refl[{r, x}]))
          end
        ),
      # What the water mirrors, the electric lamps' roads, by row.
      refl:
        List.to_tuple(
          for r <- 0..(@h - 1) do
            List.to_tuple(
              for x <- 0..(@w - 1) do
                case refl[{r, x}] do
                  {rr, rg, rb, _mirror} -> {rr, rg, rb}
                  nil -> {0, 0, 0}
                end
              end
            )
          end
        ),
      roads:
        List.to_tuple(
          for r <- 0..(@h - 1),
              do: List.to_tuple(for x <- 0..(@w - 1), do: Map.get(roads, {r, x}, 0))
        ),
      # How much of the lamps' light each cell takes: their wash, and
      # whether it is a priest, whom the flames do not light.
      albedo:
        List.to_tuple(
          for r <- 0..(@h - 1) do
            List.to_tuple(
              for x <- 0..(@w - 1) do
                {m, _, _, _, _, al, _} = cells[{r, x}]
                {al, m == @fig}
              end
            )
          end
        ),
      clouds: {cover, lit},
      lamps: lamps,
      diyas: diyas,
      lut: Palette.nearest_lut(Enum.drop(@meta.palette, -1)),
      # Set only by the tests: every shortcut below then takes its exact
      # path (`JSMath` and no margins, no precomputed dots, no rows or
      # columns passed over), so the two can be checked against each other.
      exact?: false
    }
  end

  # What a cell keeps for the frame.
  defp cell(x, r, {@water, _, _, _, _, _, _}, {_rr, _rg, _rb, mirror}) do
    y = r + 0.5
    q = (x + 0.5 - @glow_x) / 15
    gw = 1.3 + (y - @hz) * 0.15
    gx = (x + 0.5 - @glow_x) / gw
    # A narrow road of glitter straight under the glow.
    road = if gx > -3 and gx < 3, do: :math.exp(-gx * gx) * :math.exp(-(y - @hz) / 24)

    {:water, mirror, (y - @hz) / (@h - @hz),
     :math.exp(-(q * q)) * smooth(@hz + 2.5, @hz + 5.5, y), road, smooth(@h + 4, @h - 16, y)}
  end

  defp cell(x, r, {m, cr, cg, cb, fl, _al, warm}, _refl) do
    star = m == @sky and r < @ch and r + 0.5 < 24 and hash(x, r * 3 + 11) > 0.993
    star = if star, do: {1.3 + hash(x, r) * 2, hash(r, x) * 6.28}

    {:land, m == @sky, cr, cg, cb, fl, warm, star, static_halftone(x, r, cr, cg, cb, fl)}
  end

  # The dot of a cell nothing passes over this frame: its character, and
  # its colour as the palette lookup takes it (the cache key, then the
  # colour).
  defp static_halftone(x, r, cr, cg, cb, floor) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(floor + (1 - floor) * :math.pow(peak, 0.72) * 0.95)
    step = max(0, min(3, JSMath.round(level * 3 + elem(@bayer, band(r, 3) * 4 + band(x, 3)))))
    {tr, tg, tb} = tint(step, level, peak, cr, cg, cb)
    {elem(@dots, step), key(tr, tg, tb), tr, tg, tb}
  end

  # --- the halftone --------------------------------------------------------

  # The colour makes up what the dot size could not, within the dot's lift.
  defp tint(step, level, peak, cr, cg, cb) do
    want = if step != 0, do: min(1, (level + 0.06) / elem(@cover, step)), else: 0
    s = min(elem(@lift, step), (0.3 + 0.7 * want) / peak)
    {clamp(cr * s), clamp(cg * s), clamp(cb * s)}
  end

  # The nearest-colour cache's key, as `AsciiArt.Kit.Palette.nearest/4` makes it.
  defp key(r, g, b), do: bsl(cube(r), 10) ||| bsl(cube(g), 5) ||| cube(b)
  defp cube(v), do: min(31, trunc(v * 31.99))

  defp lookup({_palette, answers} = lut, key, tr, tg, tb) do
    case answers do
      %{^key => i} -> {i, lut}
      _ -> Palette.nearest(lut, tr, tg, tb)
    end
  end

  defp paint({ch, key, tr, tg, tb}, true, lut) do
    {i, lut} = lookup(lut, key, tr, tg, tb)
    {ch, i, lut}
  end

  defp paint({ch, _key, _tr, _tg, _tb}, false, lut), do: {ch, 0, lut}

  # Dot size from brightness, dithered, in the palette colour nearest its
  # hue; a star is drawn in starlight.
  defp halftone(x, r, {cr, cg, cb, floor, fade, star?}, color?, lut) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(floor + (1 - floor) * :math.pow(peak, 0.72) * 0.95) * fade
    step = max(0, min(3, JSMath.round(level * 3 + elem(@bayer, band(r, 3) * 4 + band(x, 3)))))

    cond do
      not color? ->
        {elem(@dots, step), 0, lut}

      star? ->
        {elem(@dots, step), @star, lut}

      true ->
        {tr, tg, tb} = tint(step, level, peak, cr, cg, cb)
        {i, lut} = lookup(lut, key(tr, tg, tb), tr, tg, tb)
        {elem(@dots, step), i, lut}
    end
  end

  defp dot(x, r, shade, {color?, _exact?}, lut), do: halftone(x, r, shade, color?, lut)

  # --- the lamps in a frame -------------------------------------------------

  # Aarti: each lamp is raised and turned in slow circles. For each: the
  # cells of the priest's arm, its glow and the wash it throws on the stone,
  # and its streak on the water.
  defp aarti(t) do
    @aarti
    |> Enum.with_index()
    |> Enum.map(fn {{ax, sw, sl}, i} ->
      s = sc_f(ax)
      u = 1.3 * s
      base = wl_f(ax) - 2.6 * s
      ph = t * 1.1 + i * 1.3
      fx = ax + 0.9 * u + :math.cos(ph) * 1.1 * u
      fy = base - 7.2 * u + :math.sin(ph) * 0.6 * u
      fl = 0.85 + 0.15 * :math.sin(t * 13 + i * 5) * :math.sin(t * 7.3 + i)

      {arm(ax, base, u, fx, fy), glow(fx, fy, 0.6 * u, 1.7 * u, fl),
       wash(fx, fy + 2 * u, 7.5 * s, 0.34 * fl),
       streak(fx, wl_f(fx), 0.8 * s * sw, 15 * s * sl, 0.75 * fl)}
    end)
  end

  # The arm from the shoulder to the lamp.
  defp arm(ax, base, u, fx, fy) do
    sx0 = ax + 0.62 * u
    sy0 = base - 3.8 * u
    ex = fx - sx0
    ey = fy + 0.6 * u - sy0
    el = ex * ex + ey * ey

    for r <- floor(min(sy0, fy) - 1)..floor(max(sy0, fy) + 1)//1,
        x <- floor(min(sx0, fx) - 1)..floor(max(sx0, fx) + 1)//1,
        x >= 0 and x < @w and r >= 0 and r < @h,
        px = x + 0.5 - sx0,
        py = r + 0.5 - sy0,
        q = clamp((px * ex + py * ey) / el),
        JSMath.hypot(px - q * ex, py - q * ey) < 0.28 * u,
        do: {r, x}
  end

  # A white-hot heart inside an orange halo, and the lamps' wide warm wash on
  # the stone, as {kind, rows, columns, ...}: the rows and columns are
  # upstream's loop bounds.
  defp glow(fx, fy, core, halo, amp) do
    reach = ceil(halo * 3.2)
    {:glow, box(fy, reach, @h), box(fx, reach, @w), fx, fy, core, halo, amp}
  end

  defp wash(fx, fy, halo, amp) do
    reach = ceil(halo * 2.6)
    {:wash, box(fy, reach, @h), box(fx, reach, @w), fx, fy, halo, amp}
  end

  # The first and last index i with max(0, floor(c - reach)) <= i < min(n, c + reach).
  defp box(c, reach, n) do
    last = min(n - 1, ceil(c + reach) - 1)
    {max(0, floor(c - reach)), last}
  end

  defp streak(fx, wl, width, len, amp), do: {fx, wl, width, len, amp}

  # Diyas drifting downstream, nearer ones faster: a glow and a streak each,
  # for those in view.
  defp diyas(diyas, t) do
    for {x0, y, ph, sz} <- diyas,
        near = (y - @hz) / (@h - @hz),
        x = JSMath.mod(JSMath.mod(x0 + t * (0.25 + 0.9 * near), 260) + 260, 260) - 30,
        not (x < -3 or x > @w + 3 or y < wl_f(x) + 0.8) do
      fl = 0.8 + 0.2 * :math.sin(t * 9 + ph)
      s = (0.35 + 0.9 * near) * sz

      {glow(x, y - 0.3, 0.45 + 0.3 * s, 0.6 + 1.2 * s, fl * 0.8),
       streak(x, y + 0.2, 0.3 + 0.35 * s, 2 + 5 * s, 0.6 * fl)}
    end
  end

  # The lamps' light on the stone this frame, by row (nil for a row none
  # reaches): each cell's {r, g, b}, added up source by source in upstream's
  # order and stored as its Float32Arrays store them; or 0 for none.
  defp dyn(sources, state, exact?) do
    List.to_tuple(
      for r <- 0..(@h - 1) do
        case Enum.filter(sources, &on_row?(&1, r)) do
          [] ->
            nil

          # Every source tried on every cell of the row.
          active when exact? ->
            albedo = elem(state.albedo, r)
            List.to_tuple(for x <- 0..(@w - 1), do: light(active, x, r, albedo, 0))

          active ->
            albedo = elem(state.albedo, r)

            active
            |> segments()
            |> Enum.flat_map(fn
              {a, b, []} -> List.duplicate(0, b - a)
              {a, b, over} -> for x <- a..(b - 1), do: light(over, x, r, albedo, 0)
            end)
            |> List.to_tuple()
        end
      end
    )
  end

  # The row cut where any source's columns start or end: {from, to, the
  # sources over [from, to), in order}.
  defp segments(active) do
    spans = Enum.map(active, &{&1, columns(&1)})

    spans
    |> Enum.flat_map(fn {_source, {first, last}} ->
      [min(@w, max(0, first)), min(@w, last + 1)]
    end)
    |> Enum.concat([0, @w])
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      {a, b, for({source, {first, last}} <- spans, first <= a and last >= b - 1, do: source)}
    end)
  end

  defp columns({:lamp, _r, x, _v}), do: {x, x}
  defp columns(source), do: elem(source, 2)

  defp on_row?({:lamp, lr, _x, _v}, r), do: lr == r
  defp on_row?({:wash, {first, last}, _cols, _, _, _, _}, r), do: r >= first and r <= last
  defp on_row?({:glow, {first, last}, _cols, _, _, _, _, _}, r), do: r >= first and r <= last

  # The light the sources on a row throw on one cell of it, in turn.
  defp light([], _x, _r, _albedo, acc), do: acc

  defp light([source | rest], x, r, albedo, acc),
    do: light(rest, x, r, albedo, light(source, x, r, albedo, acc))

  defp light({:lamp, _r, x, v}, x, _r2, _albedo, acc),
    do: add(acc, v, v * @flame_g * 0.95, v * @flame_b)

  defp light({:glow, _rows, {first, last}, fx, fy, core, halo, amp}, x, r, albedo, acc)
       when x >= first and x <= last do
    dx = x + 0.5 - fx
    dy = (r + 0.5 - fy) * 0.85
    d = :math.sqrt(dx * dx + dy * dy)
    # The priests are not lit.
    am = if albedo |> elem(x) |> elem(1), do: amp * 0.15, else: amp
    q = d / core
    c = :math.exp(-(q * q)) * 1.6 * am
    v = :math.exp(-d / halo) * 0.35 * am
    add(acc, c + v, c * 0.86 + v * @flame_g, c * 0.55 + v * @flame_b)
  end

  defp light({:wash, _rows, {first, last}, fx, fy, halo, amp}, x, r, albedo, acc)
       when x >= first and x <= last do
    case elem(albedo, x) do
      {a, _fig?} when a != 0 ->
        dx = x + 0.5 - fx
        dy = r + 0.5 - fy
        v = :math.exp(-:math.sqrt(dx * dx + dy * dy) / halo) * amp * a
        add(acc, v, v * @wash_g, v * @wash_b)

      _ ->
        acc
    end
  end

  defp light(_source, _x, _r, _albedo, acc), do: acc

  # A store into the Float32Arrays: what is there, plus this, rounded.
  defp add(0, ar, ag, ab), do: {fround(ar), fround(ag), fround(ab)}
  defp add({dr, dg, db}, ar, ag, ab), do: {fround(dr + ar), fround(dg + ag), fround(db + ab)}

  # The lamps' streaks on the water this frame, as %{{r, x} => warmth}, added
  # up streak by streak as upstream's Float32Array.
  defp streaks(streaks, cells) do
    Enum.reduce(streaks, %{}, fn {fx, wl, width, len, amp}, acc ->
      Enum.reduce_while(max(0, floor(wl))..(@h - 1)//1, acc, fn r, acc ->
        dy = r + 0.5 - wl
        a = :math.exp(-dy / len) * amp * smooth(-0.5, 1, dy)

        if a < 0.01 do
          {:halt, acc}
        else
          acc =
            for x <-
                  max(0, floor(fx - 3 * width - 1))..min(@w - 1, ceil(fx + 3 * width + 1) - 1)//1,
                water?(cells, r, x),
                reduce: acc do
              acc ->
                q = (x + 0.5 - fx) / width
                v = a * :math.exp(-(q * q))
                Map.update(acc, {r, x}, fround(v), &fround(&1 + v))
            end

          {:cont, acc}
        end
      end)
    end)
  end

  defp water?(cells, r, x), do: match?({:water, _, _, _, _, _}, cells |> elem(r) |> elem(x))

  # --- the frame ------------------------------------------------------------

  @impl true
  def frame(state, t, env) do
    aarti = aarti(t)
    diyas = diyas(state.diyas, t)

    # The step lamps, twinkling.
    lamps = for {r, x, ph} <- state.lamps, do: {:lamp, r, x, 0.7 + 0.3 * :math.sin(t * 5 + ph)}

    sources =
      Enum.flat_map(aarti, fn {_arm, glow, wash, _streak} -> [glow, wash] end) ++
        lamps ++ Enum.map(diyas, &elem(&1, 0))

    dref =
      streaks(
        Enum.map(aarti, &elem(&1, 3)) ++ Enum.map(diyas, &elem(&1, 1)),
        state.cells
      )

    # The boat crossing the bright reach.
    bx = JSMath.mod(JSMath.mod(159 - t * 0.1 + 24, 250) + 250, 250) - 24

    fr = %{
      t: t,
      # Starts with the long streaks over the glow.
      drift: t * 0.9 + 720,
      boat: {bx, 71 + :math.sin(t * 0.9) * 0.15},
      dyn: dyn(sources, state, state.exact?),
      # By row, as a tuple of the row's warmth, or nil for none.
      dref:
        List.to_tuple(
          for r <- 0..(@h - 1) do
            if state.exact? or Enum.any?(0..(@w - 1), &Map.has_key?(dref, {r, &1})),
              do: List.to_tuple(for x <- 0..(@w - 1), do: Map.get(dref, {r, x}, 0))
          end
        ),
      arm: Enum.flat_map(aarti, &elem(&1, 0)),
      color?: env.color?,
      exact?: state.exact?
    }

    {lines, lut} =
      Enum.map_reduce(0..(@h - 1), state.lut, fn r, lut ->
        # The arms on this row.
        fr = %{fr | arm: for({^r, x} <- fr.arm, do: x)}
        line(0, r, elem(state.cells, r), state, fr, lut, <<>>, <<>>)
      end)

    text = lines |> Enum.map(&elem(&1, 0)) |> Enum.intersperse(?\n)
    colors = if env.color?, do: IO.iodata_to_binary(Enum.map(lines, &elem(&1, 1)))
    {text, colors, %{state | lut: lut}}
  end

  defp line(@w, _r, _cells, _state, _fr, lut, chars, colors), do: {{chars, colors}, lut}

  defp line(x, r, cells, state, fr, lut, chars, colors) do
    {ch, i, lut} = px(x, r, elem(cells, x), state, fr, lut)
    line(x + 1, r, cells, state, fr, lut, <<chars::binary, ch::binary>>, <<colors::binary, i>>)
  end

  defp px(x, r, cell, state, fr, lut) do
    dyn = dyn_at(fr.dyn, r, x)
    arm? = fr.arm != [] and x in fr.arm
    {bx, by} = fr.boat
    lx = x + 0.5 - bx
    boat? = lx > -14 and lx < 15 and r > by - 11 and r < by + 11

    case shade(cell, x, r, state, fr) do
      # Nothing passes over it this frame.
      :still when dyn == 0 and not arm? and not boat? and not fr.exact? ->
        paint(elem(cell, 8), fr.color?, lut)

      shaded ->
        {cr, cg, cb, floor, fade, star?} =
          if shaded == :still, do: still(cell), else: shaded

        {cr, cg, cb, floor, star?} =
          if boat?,
            do: boat(cell, {lx, by, r}, {cr, cg, cb, floor, star?}),
            else: {cr, cg, cb, floor, star?}

        # (No light is added as nothing, unless the exact path is forced.)
        dyn = if dyn == 0 and fr.exact?, do: {0.0, 0.0, 0.0}, else: dyn
        {cr, cg, cb, floor} = lamplight(dyn, arm?, cr, cg, cb, floor)
        dot(x, r, {cr, cg, cb, floor, fade, star?}, {fr.color?, fr.exact?}, lut)
    end
  end

  defp still({:land, _sky?, cr, cg, cb, floor, _warm, _star, _static}),
    do: {cr, cg, cb, floor, 1, false}

  defp dyn_at(dyn, r, x) do
    case elem(dyn, r) do
      nil -> 0
      row -> elem(row, x)
    end
  end

  # The priests' raised arms are dark, lit only a little by their lamps;
  # everything else takes the lamps' light.
  defp lamplight(dyn, true, _cr, _cg, _cb, _floor) do
    {dr, dg, db} = if dyn == 0, do: {0, 0, 0}, else: dyn
    {0.035 + dr * 0.12, 0.022 + dg * 0.12, 0.035 + db * 0.12, 0.02}
  end

  defp lamplight(0, false, cr, cg, cb, floor), do: {cr, cg, cb, floor}

  defp lamplight({dr, dg, db}, false, cr, cg, cb, floor),
    do: {cr + dr, cg + dg, cb + db, floor}

  # The boat and its dark reflection.
  defp boat(cell, {lx, by, r}, {cr, cg, cb, floor, star?}) do
    water? = elem(cell, 0) == :water

    {cov, rc} =
      for sy2 <- 0..1, sx2 <- 0..1, reduce: {0, 0} do
        {cov, rc} ->
          px = (lx - 0.25 + sx2 * 0.5) / @bs
          py = (by - (r + 0.25 + sy2 * 0.5)) / @bs
          cov = if boat?(px, py), do: cov + 1, else: cov
          rc = if water? and boat?(px, -py * 0.9), do: rc + 1, else: rc
          {cov, rc}
      end

    cov = cov / 4
    rc = rc / 4

    cond do
      cov > 0 ->
        {mix(cr, 0.035, cov), mix(cg, 0.022, cov), mix(cb, 0.035, cov), mix(floor, 0.02, cov),
         false}

      rc > 0 ->
        {cr * (1 - 0.8 * rc), cg * (1 - 0.8 * rc), cb * (1 - 0.75 * rc), floor, star?}

      true ->
        {cr, cg, cb, floor, star?}
    end
  end

  # --- each kind in a frame -------------------------------------------------

  defp shade({:land, true, cr, cg, cb, floor, warm, star, _static}, x, r, state, fr)
       when r < @ch do
    {cover, clit} = state.clouds
    sx = x + fr.drift
    ix = floor(sx)
    fx = sx - ix
    i0 = rem(ix, @cw)
    i1 = rem(ix + 1, @cw)
    row = elem(cover, r)
    c0 = elem(row, i0)
    c = c0 + (elem(row, i1) - c0) * fx

    cond do
      c > 0.01 ->
        # High streaks glow rose from below; low ones stand dark against the
        # afterglow with only their undersides lit, gold near the glow.
        row = elem(clit, r)
        l0 = elem(row, i0)
        l = l0 + (elem(row, i1) - l0) * fx
        lit = mix(0.3 + 0.7 * l, 0.9 * l * l, smooth(12, 30, r + 0.5))
        {tr, tg, tb} = ramp(0.56 + 0.38 * warm + 0.08 * l)

        {mix(cr, mix(0.075, tr, lit), c), mix(cg, mix(0.05, tg, lit), c),
         mix(cb, mix(0.15, tb, lit), c), mix(floor, 0.06, c * (1 - lit)), 1, false}

      star != nil ->
        {speed, phase} = star
        tw = 0.4 + 0.25 * :math.sin(fr.t * speed + phase)
        {max(cr, tw * 0.9), max(cg, tw * 0.88), max(cb, tw), floor, 1, true}

      true ->
        :still
    end
  end

  defp shade({:land, _sky?, _cr, _cg, _cb, _floor, _warm, _star, _static}, _x, _r, _state, _fr),
    do: :still

  defp shade({:water, mirror, v, reach, road, fade}, x, r, state, fr) do
    t = fr.t
    y = r + 0.5

    w =
      0.6 * noise(x * 0.05 + t * 0.08, y * 0.45 - t * 0.45) +
        0.4 * noise(x * 0.16 - t * 0.15, y * 0.95 - t * 0.9)

    swell = 0.55 + 0.9 * w
    wob = (noise(x * 0.04 + 7, y * 0.3 - t * 0.6) - 0.5) * (1.2 + 4 * v)
    sx = (x + wob) |> max(0) |> min(@w - 1.001)
    i0 = trunc(sx)
    fx = sx - i0
    dash = smooth(0.25, 0.75, noise(x * 0.12 + 3, y * 0.8 - t * 1.1))
    # Broken bands, except in the bright reach under the glow.
    da = mix(0.15 + 1.1 * dash, 0.7 + 0.5 * dash, reach)
    {rr, rg, rb} = refl_at(state.refl, r, i0, fx)
    cr = 0.035 * swell + rr * da
    cg = 0.045 * swell + rg * da
    cb = 0.12 * swell + rb * da

    # The lamplit stone above, given back in broken bands.
    {cr, cg, cb} =
      case mirror && dyn_at(fr.dyn, elem(mirror, 0), elem(mirror, 1)) do
        {dr, dg, db} -> {cr + dr * 0.4 * da, cg + dg * 0.4 * da, cb + db * 0.4 * da}
        _ -> {cr, cg, cb}
      end

    fl = (warm_at(fr.dref, r, i0, fx) + road_at(state.roads, r, i0, fx)) * (0.2 + 1.1 * dash)
    cr = cr + fl
    cg = cg + fl * @flame_g
    cb = cb + fl * @flame_b

    # A narrow road of glitter straight under the glow.
    {cr, cg, cb} =
      if road == nil do
        {cr, cg, cb}
      else
        rip = noise(x * 0.45 + y * 0.1 - t * 0.3, y * 1.3 - t * 1.6)
        glint = smooth(0.42, 0.78, 0.45 * w + 0.55 * rip) * road

        {cr + (1.0 * glint + 0.12 * road), cg + (0.78 * glint + 0.07 * road),
         cb + (0.42 * glint + 0.04 * road)}
      end

    {cr, cg, cb, 0.12, fade, false}
  end

  defp refl_at(refl, r, i0, fx) do
    row = elem(refl, r)
    {ar, ag, ab} = elem(row, i0)
    {br, bg, bb} = elem(row, i0 + 1)
    {ar + (br - ar) * fx, ag + (bg - ag) * fx, ab + (bb - ab) * fx}
  end

  defp warm_at(dref, r, i0, fx) do
    case elem(dref, r) do
      nil ->
        0

      row ->
        a = elem(row, i0)
        a + (elem(row, i0 + 1) - a) * fx
    end
  end

  defp road_at(roads, r, i0, fx) do
    row = elem(roads, r)
    a = elem(row, i0)
    a + (elem(row, i0 + 1) - a) * fx
  end
end
