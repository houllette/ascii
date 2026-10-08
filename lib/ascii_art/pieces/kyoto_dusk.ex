defmodule AsciiArt.Pieces.KyotoDusk do
  @moduledoc """
  A pagoda at dusk behind a cherry tree lit by a stone lantern.

  A five-storey pagoda dark against an indigo to rose sky with a thin
  crescent moon, a temple pond holding its reflection, and in front a cherry
  tree in full bloom lit from below by a stone lantern. Petals fall and drift
  through the frame, the lantern flickers, the pond shivers.

  Shaded in colour cell by cell, then drawn as a halftone: each cell is a dot
  sized by its brightness, ordered-dithered, in the palette colour nearest its
  hue, with the colour brightened or dimmed to make up for the dot's size.

  Ported from `src/pieces/kyoto-dusk.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Hash, Palette, Scene}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "kyoto dusk",
    category: :scenes,
    note: "a pagoda at dusk behind a cherry tree lit by a stone lantern",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#0b0a16",
    palette: [
      "#1c1d4a",
      "#262759",
      "#33316b",
      "#433d7c",
      "#574a8c",
      "#6e5a9a",
      "#8a5a92",
      "#a8668f",
      "#c4748f",
      "#db8a95",
      "#ec9f9c",
      "#f6b8a8",
      "#fbd0b8",
      "#fff1d8",
      "#fffaf0",
      "#7e5f9e",
      "#f9d3dc",
      "#f2b2c4",
      "#e28fab",
      "#c66e92",
      "#9c5279",
      "#74405f",
      "#ffd9a0",
      "#ffbb6a",
      "#f29a4a",
      "#d0763a",
      "#a35a35",
      "#2a2240",
      "#3a2c50",
      "#4a3860",
      "#5b4f86",
      "#7a6aa0",
      "#2c3a3a",
      "#3d4c46",
      "#56604f",
      "#9a6aa0",
      "#b47ea6",
      "#4a3038",
      "#6a4448",
      "#2b3a6a",
      "#3e4f86"
    ]
  }

  @w 200
  @h 100
  # The far bank of the pond, where the pagoda stands.
  @shore 80
  # The pagoda's axis.
  @px 141
  @moon_x 176
  @moon_y 17
  # The lantern's axis, foot and scale, and its lit opening.
  @lx 53
  @lb 98
  @ls 1.8
  @lamp_y @lb - (@lb - 83) * @ls
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()

  @sky 0
  @hill 1
  @town 2
  @pagoda 3
  @pond 4
  @bank 5
  @tree 6
  @bloom 7
  @stone 8
  @flame 9

  # Where each roof's eave sits, each roof's half-width, each storey's.
  @eave {68.5, 58, 48.5, 40, 32.5}
  @roof {14.5, 13.4, 12.3, 11.2, 10.1}
  @body {6.4, 5.9, 5.4, 4.9, 4.4}

  # The cherry tree's skeleton: {ax, ay, bx, by, w0, w1}.
  @branches [
    # trunk, leaning up and to the right
    {16, 101, 20, 86, 5.2, 4.4},
    {20, 86, 27, 70, 4.4, 3.6},
    {27, 70, 31, 58, 3.6, 3},
    # limbs
    {31, 58, 50, 46, 3, 2.1},
    {50, 46, 74, 37, 2.1, 1.4},
    {74, 37, 98, 31, 1.4, 0.9},
    {98, 31, 116, 30, 0.9, 0.5},
    {31, 58, 24, 40, 2.6, 1.8},
    {24, 40, 12, 26, 1.8, 1.1},
    {12, 26, 0, 18, 1.1, 0.7},
    {29, 50, 42, 30, 2, 1.3},
    {42, 30, 52, 19, 1.3, 0.8},
    {52, 19, 70, 13, 0.8, 0.5},
    {50, 46, 60, 52, 1.2, 0.7},
    {74, 37, 86, 44, 1, 0.5},
    {42, 30, 66, 24, 1, 0.6},
    {66, 24, 90, 21, 0.6, 0.4},
    {24, 40, 34, 25, 1, 0.6},
    {12, 26, 6, 16, 0.7, 0.4},
    {98, 31, 104, 40, 0.6, 0.35},
    # sprays drooping low over the lantern
    {40, 51, 44, 58, 1.1, 0.4},
    {58, 43, 62, 55, 0.9, 0.35},
    {70, 38, 76, 47, 0.7, 0.3}
  ]

  # Thin streaks of cloud low in the sky: their width, which wraps, and rows.
  @cw 500
  @c0 34
  @c1 68

  @impl true
  def meta, do: @meta

  # Called for nearly every cell: local, so they inline.
  @compile {:inline, clamp: 1, smooth: 3, mix: 3, index: 1, js_round: 1, lerp: 3, tint: 2}
  # Floats out, so the shading stays in float arithmetic.
  defp clamp(v) when v < 0, do: 0.0
  defp clamp(v) when v > 1, do: 1.0
  defp clamp(v), do: v

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  # `Math.round`, as `AsciiArt.JSMath.round/1` does it for a float.
  defp js_round(x) do
    c = ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end

  # `Math.min(1024, (v * 256) | 0)`, for the tone curve.
  defp index(v), do: min(1024, trunc(v * 256))

  defdelegate noise(x, y, period), to: Scene
  defdelegate fbm(x, y, octaves, period), to: Scene

  defp f32(v), do: JSMath.fround(v)

  # Distance from a point to a segment, and how far along it the nearest point is.
  defp seg(px, py, ax, ay, bx, by) do
    dx = bx - ax
    dy = by - ay
    k = clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
    ex = ax + dx * k - px
    ey = ay + dy * k - py
    {:math.sqrt(ex * ex + ey * ey), k}
  end

  # --- the pagoda --------------------------------------------------------------

  # The pagoda, in cells about its axis: a shade code or 0 for air. 1 body,
  # 2 roof top, 3 roof underside, 4 roof rim, 5 spire, 6 lit doorway.
  defp pagoda(dx, y) do
    ax = abs(dx)

    # Stone base.
    if y >= 76 and y < @shore + 0.5,
      do: if(ax <= 9.5 - if(y < 77, do: 1, else: 0), do: 1, else: 0),
      else: storey(ax, y, 0)
  end

  defp storey(ax, y, 5), do: spire(ax, y)

  defp storey(ax, y, i) do
    e = elem(@eave, i)
    body = elem(@body, i)
    # A roof: thin at its upturned tips, rising in a shallow concave curve to the body.
    u = ax / elem(@roof, i)
    roof = if u <= 1, do: roof(u, e, y), else: 0
    # The storey beneath this roof, up from the roof below it (or the base).
    floor_y = if i == 0, do: 76, else: elem(@eave, i - 1) - 3.6

    cond do
      roof != 0 -> roof
      y >= e + 0.6 and y < floor_y and ax <= body -> body(i, ax, y, e, body)
      i > 0 and y >= e + 0.6 and y < e + 2 and ax <= body + 1.2 -> 3
      true -> storey(ax, y, i + 1)
    end
  end

  defp roof(u, e, y) do
    lift = 3.5 * u * u * u * u
    bottom = e - lift + 0.6
    top = e - lift - 1.2 - 3.6 * :math.pow(1 - u, 1.7)

    cond do
      not (y >= top and y < bottom) -> 0
      y < top + 0.9 -> 4
      y > bottom - 1.0 -> 3
      true -> 2
    end
  end

  defp body(i, ax, y, e, body) do
    cond do
      i == 0 and ax <= 1 and y > 72 and y < 75.5 -> 6
      # A railed balcony under each roof.
      y < e + 2 and ax <= body + 1.2 -> 3
      true -> 1
    end
  end

  # The spire: a mast with nine rings and a flame-shaped finial.
  defp spire(ax, y) do
    top = elem(@eave, 4) - 1.2 - 3.6 - 0.2

    cond do
      not (y < top and y >= 9) ->
        0

      # The roof box.
      y >= top - 1.5 ->
        if ax <= 2.4, do: 3, else: 0

      y >= 15 ->
        if ax <= if(band(floor((y - 15) / 1.2), 1) != 0, do: 1.4, else: 0.55), do: 5, else: 0

      y >= 12 ->
        if ax <= 1.3 - (y - 12) * 0.2, do: 5, else: 0

      true ->
        if ax <= 0.6, do: 5, else: 0
    end
  end

  # --- the still picture -------------------------------------------------------

  defp sky_at(x, y) do
    v = clamp(y / @shore)
    # Indigo overhead, through violet, to rose and peach low in the west (left).
    west = :math.exp(-abs(x - 80) / 120)
    a = smooth(0, 0.5, v)
    r = mix(0.07, 0.22, a)
    g = mix(0.07, 0.14, a)
    b = mix(0.25, 0.38, a)
    a = smooth(0.42, 0.86, v)
    r = mix(r, 0.52, a)
    g = mix(g, 0.32, a)
    b = mix(b, 0.58, a)
    a = smooth(0.78, 0.98, v) * (0.55 + 0.45 * west)
    r = mix(r, 1.0, a)
    g = mix(g, 0.62, a)
    b = mix(b, 0.48, a)
    band = :math.exp(-abs(y - 74) / 4) * west * 0.18
    r = r + band
    g = g + band * 0.66
    b = b + band * 0.45
    # A faint unevenness, so no stretch of sky is one flat tone.
    veil = 0.86 + 0.28 * fbm(x * 0.035, y * 0.09, 3, 0)
    r = r * veil
    g = g * veil
    b = b * veil
    # The moon's halo.
    dx = x - @moon_x
    dy = y - @moon_y
    d = :math.sqrt(dx * dx + dy * dy)
    halo = :math.exp(-d / 5) * 0.24 + :math.exp(-d / 16) * 0.07
    {r + halo * 0.75, g + halo * 0.72, b + halo}
  end

  # Low in the west where the glow is, rising behind the pagoda and the town.
  defp hill_a(x),
    do: 77.5 - (3 + 13 * smooth(70, 175, x)) * (0.3 + 1.1 * fbm(x * 0.022 + 3, 1, 4, 0))

  defp hill_b(x), do: 77 - 2.5 * fbm(x * 0.04 + 9, 2, 4, 0)

  # Low tiled roofs along the far bank, a few lit.
  defp town(x) do
    i = floor((x + 3) / 11)
    f = (x + 3) / 11 - i
    # A hipped roof: a short level ridge, sloping ends, a gap between houses.
    h = 2 + Hash.scene(i, 5) * 2.5
    e = abs(f - 0.5) * 2
    if e > 0.86, do: @shore, else: @shore - 1 - h + max(0, e - 0.35) * 6
  end

  defp bank_x(y), do: 38 + (y - @shore) * 2.3 + 4 * fbm(y * 0.2, 4, 2, 0)

  # What each cell is, before the lantern and the tree: {material, r, g, b, floor, warmth}.
  defp picture(x, r) do
    y = r + 0.5
    xc = x + 0.5

    if y < @shore do
      {cr, cg, cb} = sky_at(xc, y)

      {m, cr, cg, cb, fl} =
        {@sky, cr, cg, cb, 0.04}
        |> hills(xc, y)
        |> houses(xc, y)
        |> pagoda_cell(xc, y)

      {m, f32(cr), f32(cg), f32(cb), f32(fl), 0.0}
    else
      near_bank(x, r, xc, y)
    end
  end

  # Distant hills in haze, then a nearer ridge.
  defp hills({m, cr, cg, cb, fl}, xc, y) do
    ha = hill_a(xc)

    {m, cr, cg, cb} =
      if y >= ha do
        # The Higashiyama hills, flat and violet in the haze.
        {s0, s1, s2} = sky_at(xc, ha)
        d = smooth(ha, ha + 8, y)
        # Wooded slopes: clumps of trees in the haze.
        tex = fbm(xc * 0.3, y * 0.45, 3, 0)
        a = 0.6 + 0.2 * d + 0.25 * (tex - 0.5)
        # The ridge line catches the afterglow.
        lip = smooth(ha + 1.4, ha, y) * 0.3

        {@hill, mix(mix(s0, 0.14, a), s0 * 1.1, lip), mix(mix(s1, 0.08, a), s1 * 1.05, lip),
         mix(mix(s2, 0.24, a), s2, lip)}
      else
        {m, cr, cg, cb}
      end

    hb = hill_b(xc)

    if y >= hb do
      tex = fbm(xc * 0.3, y * 0.3, 3, 0)
      # Mist settling along the water.
      mist = smooth(hb + 1, @shore, y) * 0.5

      {@hill, mix(0.1 + 0.05 * tex, 0.7, mist), mix(0.07 + 0.03 * tex, 0.44, mist),
       mix(0.17 + 0.05 * tex, 0.58, mist), fl}
    else
      {m, cr, cg, cb, fl}
    end
  end

  defp houses({m, cr, cg, cb, fl}, xc, y) do
    top = town(xc)

    if y >= top and xc > 70 do
      # The roof ridges catch the sky.
      tf = abs(:math.fmod((xc + 3) / 11, 1.0) - 0.5) * 2

      {cr, cg, cb, fl} =
        if y < top + 0.9 and tf < 0.45, do: {0.5, 0.31, 0.44, 0.06}, else: {0.08, 0.06, 0.14, fl}

      # A few lit shoji under the eaves.
      if y > @shore - 1.6 and y < @shore - 0.5 and :math.fmod(xc, 4.0) < 1.2 and
           Hash.scene(floor(xc / 4), 7) > 0.74,
         do: {@town, 1, 0.66, 0.32, 0.3},
         else: {@town, cr, cg, cb, fl}
    else
      {m, cr, cg, cb, fl}
    end
  end

  defp pagoda_cell({m, cr, cg, cb, fl}, xc, y) do
    dx = xc - @px
    # The sky to the west lights its left.
    rim = :math.exp(-abs(dx + 4) / 30)

    # Dark timber; the tiled roofs pick up the sky, their ridges most of all.
    case pagoda(dx, y) do
      0 -> {m, cr, cg, cb, fl}
      1 -> {@pagoda, 0.07, 0.05, 0.12, fl}
      2 -> {@pagoda, 0.2 + 0.08 * rim, 0.13 + 0.03 * rim, 0.27 + 0.04 * rim, fl}
      3 -> {@pagoda, 0.05, 0.04, 0.1, fl}
      4 -> {@pagoda, 0.9 * rim + 0.25, 0.5 * rim + 0.15, 0.5 * rim + 0.3, fl}
      5 -> {@pagoda, 0.3 + 0.2 * if(dx < 0, do: 1, else: 0), 0.22, 0.32, fl}
      6 -> {@pagoda, 0.7, 0.42, 0.24, 0.2}
    end
  end

  # The pond, and the near bank where the lantern stands.
  defp near_bank(x, r, xc, y) do
    edge = bank_x(y)

    if xc < edge do
      tex = fbm(xc * 0.3, y * 0.5, 3, 0)

      {cr, cg, cb, fl} =
        cond do
          # The stone lip of the pond.
          xc > edge - 2.6 ->
            s = 0.85 + 0.3 * Hash.scene(x * 3, r * 5)
            {0.45 * s, 0.38 * s, 0.46 * s, 0.1}

          # Fallen petals on the moss.
          Hash.scene(x * 7, r * 3) > 0.975 - 0.015 * smooth(@shore + 4, @h, y) ->
            {0.42, 0.22, 0.3, 0.06}

          true ->
            {0.08 + 0.05 * tex, 0.08 + 0.05 * tex, 0.1 + 0.05 * tex, 0.12}
        end

      {@bank, f32(cr), f32(cg), f32(cb), f32(fl), 1.0}
    else
      {@pond, 0.0, 0.0, 0.0, f32(0.12), 0.0}
    end
  end

  # --- the stone lantern -------------------------------------------------------

  defp lantern(dx, y) do
    ax = abs(dx)

    cond do
      # The lit opening.
      ax <= 1.7 and y >= 80.8 and y < 84.8 -> 2
      # The roof, flaring out with upturned corners.
      y >= 76.5 and y < 80 -> lantern_roof(ax, y)
      # Finial.
      y >= 73.5 and y < 76.5 -> if ax <= 1.3 - abs(y - 75) * 0.25 or ax <= 0.5, do: 3, else: 0
      ax <= stone(y) -> 1
      true -> 0
    end
  end

  # The stone's half-width: foot, post, platform and firebox; -1 above them.
  defp stone(y) when y >= 93.5 and y < @lb, do: 4.2 - if(y < 94.5, do: 0.8, else: 0)
  defp stone(y) when y >= 87 and y < 93.5, do: 1.4
  defp stone(y) when y >= 85.5 and y < 87, do: 3.6 - if(y < 86.2, do: 0.6, else: 0)
  defp stone(y) when y >= 80 and y < 85.5, do: 2.9
  defp stone(_y), do: -1

  defp lantern_roof(ax, y) do
    u = (80 - y) / 3.5
    hw = 5.6 - 4.1 * :math.pow(u, 0.8) + if(y > 79.2, do: 0.6, else: 0)
    if ax <= hw, do: 3, else: 0
  end

  # Drawn a size up from its plan, standing on the bank.
  defp at(xc, y), do: lantern((xc - @lx) / @ls, @lb - (@lb - y) / @ls)

  defp lantern_cell(x, r, cell) when r >= 45 and x >= @lx - 14 and x <= @lx + 14 do
    y = r + 0.5
    xc = x + 0.5
    py = @lb - (@lb - y) / @ls
    pdx = (xc - @lx) / @ls

    case at(xc, y) do
      0 ->
        cell

      2 ->
        # Hottest at the heart of the firebox.
        c = :math.exp(-(pdx * pdx * 0.5 + (py - 82.8) * (py - 82.8) * 0.35))

        {@flame, f32(0.85 + 0.15 * c), f32(0.5 + 0.38 * c), f32(0.2 + 0.4 * c * c), f32(0.35),
         0.0}

      l ->
        # Dark granite, its top surfaces catching the last of the sky.
        g = 0.8 + 0.4 * Hash.scene(x * 5, r * 3)
        edge = if at(xc, y - 1) == 0, do: 1, else: 0
        cr = f32((0.05 + 0.22 * edge) * g)
        cg = f32((0.04 + 0.14 * edge) * g)
        cb = f32((0.08 + 0.2 * edge) * g)

        # The roof's underside and the platform take the flame's light.
        {cr, cg, cb} =
          if (l == 3 and py > 78.6) or (py >= 85.5 and py < 86.4) do
            f = :math.exp(-abs(py - 82.8) / 3) * 0.75
            {f32(cr + f), f32(cg + f * 0.5), f32(cb + f * 0.18)}
          else
            {cr, cg, cb}
          end

        {@stone, cr, cg, cb, f32(0.02), f32(0.75)}
    end
  end

  defp lantern_cell(_x, _r, cell), do: cell

  # --- the cherry tree ---------------------------------------------------------

  # Short twigs off every limb, reaching up and out.
  defp twigs do
    @branches
    |> Enum.with_index()
    |> Enum.drop(3)
    |> Enum.flat_map(fn {{ax, ay, bx, by, w0, w1}, b} ->
      ang = :math.atan2(by - ay, bx - ax)

      for j <- 0..2 do
        k = 0.25 + 0.65 * Hash.scene(b * 7 + j, 31)
        sx = mix(ax, bx, k)
        sy = mix(ay, by, k)
        turn = if(band(j, 1) != 0, do: 1, else: -1) * (0.5 + 0.6 * Hash.scene(b, j + 40))
        len = 4 + 7 * Hash.scene(b + j, 41)
        a2 = ang + turn - 0.25

        {sx, sy, sx + :math.cos(a2) * len, sy + :math.sin(a2) * len, mix(w0, w1, k) * 0.55, 0.3}
      end
    end)
  end

  # Blossom clumps all along the limbs and twigs, thickest at their ends.
  defp clusters(branches) do
    limbs = length(@branches)

    branches
    |> Enum.with_index()
    |> Enum.drop(3)
    |> Enum.flat_map(fn {{ax, ay, bx, by, w0, _w1}, b} ->
      n = 1 + JSMath.round(JSMath.hypot(bx - ax, by - ay) / 1.7)
      # Only the drooping sprays (and their twigs) hang below the crown.
      spray? = (b >= limbs - 3 and b < limbs) or b >= limbs + 3 * (limbs - 6)

      for i <- 0..n,
          k = i / n,
          not (k < 0.3 and w0 > 2),
          cx = mix(ax, bx, k) + (Hash.scene(b * 13 + i, 7) - 0.5) * 6,
          cy = mix(ay, by, k) + (Hash.scene(b * 5 + i, 11) - 0.5) * 4.5 - 1,
          # The crown is domed: thinner toward its top, never cut by the frame.
          dome = 9 + 10 * :math.pow(clamp(abs(cx - 52) / 70), 1.6),
          not (cx > 122 or cy < dome or cy > if(spray?, do: 55, else: 47)),
          do: {cx, cy, 1.4 + 1.6 * Hash.scene(b * 3 + i, 17) + 0.8 * k}
    end)
  end

  defp tree_cell(x, _r, cell, _branches, _clusters) when x >= 130, do: cell

  defp tree_cell(x, r, cell, branches, clusters) do
    y = r + 0.5
    xc = x + 0.5
    # Blossom density: soft clouds, broken up by noise into clumps.
    {d, _best, up} =
      Enum.reduce(clusters, {0, 0, 0}, fn {cx, cy, rad}, {d, best, up} = acc ->
        dx = xc - cx
        dy = (y - cy) * 1.15
        q = (dx * dx + dy * dy) / (rad * rad)

        if q < 3 do
          c = :math.exp(-q * 1.4)
          if c > best, do: {d + c, c, (dy + dx * 0.4) / rad}, else: {d + c, best, up}
        else
          acc
        end
      end)

    # Big holes where the sky shows through, small ones between clumps.
    n = fbm(xc * 0.11, y * 0.15, 3, 0)
    n2 = noise(xc * 0.5, y * 0.6, 0)
    bloom = (1 - :math.exp(-d * 1.5)) * (0.15 + 1.35 * n) * (0.75 + 0.5 * n2)

    {on_branch?, bw} =
      Enum.reduce(branches, {false, 0}, fn {ax, ay, bx, by, w0, w1}, {on?, bw} ->
        {dist, kk} = seg(xc, y, ax, ay, bx, by)
        w = mix(w0, w1, kk) * 0.5 + 0.15

        if dist < w,
          do: {true, max(bw, dist / w * if(xc < ax + (bx - ax) * kk, do: -1, else: 1))},
          else: {on?, bw}
      end)

    cond do
      on_branch? and bloom < 0.85 ->
        # Dark bark threading through the blossom; the side toward the lantern catches it.
        lit = smooth(0.35, 1, bw)
        {@tree, f32(0.05 + 0.03 * lit), f32(0.035 + 0.01 * lit), f32(0.07), 0.0, f32(0.8)}

      bloom > 0.5 ->
        # Each spray pale pink on top where the sky lights it, deep rose beneath.
        inner = Hash.scene(x * 3, r * 7)
        b = clamp(0.62 - 0.6 * up + 0.26 * (inner - 0.5) - 0.3 * smooth(0.75, 0.5, bloom))
        b = mix(b, 0.12, smooth(0.3, 1.1, up))
        # The lower crown sits in its own shade.
        b = b * (1 - 0.3 * smooth(28, 48, y))

        {@bloom, f32(0.34 + 0.64 * b), f32(0.08 + 0.62 * b * b), f32(0.2 + 0.5 * b), f32(0.1),
         1.0}

      true ->
        cell
    end
  end

  # The lantern's light: how far each cell sits from the lit opening.
  defp glow(x, r, m) do
    dx = x + 0.5 - @lx
    dy = (r + 0.5 - @lamp_y) * 1.1
    d = :math.sqrt(dx * dx + dy * dy)
    g = f32(:math.exp(-d / 4) * 0.6 + :math.exp(-d / 11) * 0.32 + :math.exp(-d / 32) * 0.1)

    cond do
      # The blossom overhead takes the lamp's light from below, from further off.
      m in [@bloom, @tree] ->
        f32(g + :math.exp(-d / 11) * 1.6)

      # And a pool of light on the moss round its foot.
      m == @bank ->
        px = (x + 0.5 - @lx) / 20
        py = (r + 0.5 - @lb + 3) / 8
        f32(g + :math.exp(-(px * px + py * py)) * 0.6)

      true ->
        g
    end
  end

  @impl true
  def init(_options) do
    plain = for r <- 0..(@h - 1), x <- 0..(@w - 1), do: picture(x, r)
    # The reflection source: the far side before the tree covers it.
    mirror = plain |> Enum.map(fn {_, cr, cg, cb, _, _} -> {cr, cg, cb} end) |> List.to_tuple()
    branches = @branches ++ twigs()
    clusters = clusters(branches)

    cells =
      plain
      |> Enum.with_index()
      |> Enum.map(fn {cell, k} ->
        {x, r} = {rem(k, @w), div(k, @w)}
        cell = lantern_cell(x, r, cell)
        cell = tree_cell(x, r, cell, branches, clusters)
        {m, _, _, _, _, _} = cell
        {cell, glow(x, r, m)}
      end)
      |> List.to_tuple()

    tone =
      List.to_tuple(
        for i <- 0..1024 do
          v = i / 256
          f32(if v < 0.75, do: v, else: 0.75 + 0.25 * (1 - :math.exp(-(v - 0.75) * 4)))
        end
      )

    # The peak and its power, by the brightest channel's step on the tone curve.
    peaks =
      List.to_tuple(
        for i <- 0..1024 do
          peak = max(elem(tone, i), 1.0e-4)
          {peak, :math.pow(peak, 1.1)}
        end
      )

    %{
      lut: Palette.nearest_lut(@meta.palette),
      rows: rows(cells, tone, peaks),
      mirror: mirror,
      mat:
        cells
        |> Tuple.to_list()
        |> Enum.map(fn {{m, _, _, _, _, _}, g} -> {m, g} end)
        |> List.to_tuple(),
      cover: clouds(),
      stars: stars(cells),
      petals: petals(),
      floaters: floaters(),
      moon: moon(),
      memo: fresh_memo(),
      tone: tone,
      peaks: peaks,
      # Tests turn the fast path off (the memo) to check that frames come out
      # the same without it.
      exact?: false
    }
  end

  defp fresh_memo, do: List.duplicate(List.duplicate(:none, @w), @h)

  defp dith(x, r) do
    k = r * @w + x
    f32(elem(@bayer, band(r, 3) * 4 + band(x, 3)) * 0.4 + (Hash.scene(k, 77) - 0.5) * 0.5)
  end

  # Each cell as the frame shades it, row by row.
  defp rows(cells, tone, peaks) do
    for r <- 0..(@h - 1) do
      for x <- 0..(@w - 1) do
        {{m, cr, cg, cb, fl, wm}, glow} = elem(cells, r * @w + x)
        dith = dith(x, r)

        cond do
          m == @pond -> pond_spec(x, r, glow, fl, dith)
          m == @flame -> {:flame, dith, fl}
          wm > 0 -> {:warm, dith, fl, cr, cg, cb, glow, wm}
          m == @sky and r >= @c0 and r < @c1 -> {:cloud, dith, fl, cr, cg, cb, glow, cloud_sun(x)}
          m == @sky -> {:sky, dith, fl, cr, cg, cb, glow}
          true -> still(index(cr), index(cg), index(cb), fl, dith, tone, peaks)
        end
      end
      |> then(&{r, row_consts(r), &1})
    end
  end

  # A cell that never changes: its dot and the colour it asks for.
  defp still(ir, ig, ib, fl, dith, tone, peaks) do
    {step, want} = level(ir, ig, ib, fl, 1.0, dith, peaks)
    {:still, dith, elem(@dots, step), want_rgb(ir, ig, ib, step, want, tone, peaks)}
  end

  defp cloud_sun(x), do: 0.6 + 0.4 * :math.exp(-abs(x - 80) / 90)

  # For the pond's rows: {depth, y * 1.7, the wobble's reach, y * 1.1, the row
  # read upside down (a little stretched), how bright it reads, the fade}.
  defp row_consts(r) when r + 0.5 >= @shore do
    y = r + 0.5
    depth = (y - @shore) / (@h - @shore)

    {depth, y * 1.7, 0.05 + 0.8 * depth, y * 1.1, @shore - 1 - (r - @shore) * 1.35,
     mix(0.95, 0.6, smooth(@shore + 1, @shore + 6, y)), smooth(@h + 2, @h - 9, y)}
  end

  # For the cloud's rows: the sunlight on their undersides.
  defp row_consts(r) when r >= @c0 and r < @c1, do: 0.45 + 0.55 * smooth(@c0, @c1, r + 0.5)

  defp row_consts(_r), do: nil

  defp pond_spec(x, r, glow, fl, dith) do
    y = r + 0.5
    depth = (y - @shore) / (@h - @shore)
    # The lantern's light laid on the water as a broken warm streak.
    streak = :math.exp(-abs(x + 0.5 - @lx - 9 - (y - @shore) * 0.25) / (3.5 + depth * 3))
    {:pond, dith, fl, x * 0.14, streak, glow}
  end

  # Thin streaks of cloud low in the sky, dark violet, their undersides lit by
  # the set sun; they wrap so they can drift forever.
  defp clouds do
    for r <- @c0..(@c1 - 1) do
      y = r + 0.5

      row =
        for x <- 0..(@cw - 1) do
          d = cloud_density(x, y)

          {f32(smooth(0.56, 0.7, d)), f32(clamp(0.5 + (d - cloud_density(x - 1, y + 2.2)) * 7))}
        end

      {row |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
       row |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
    end
    |> List.to_tuple()
  end

  defp cloud_density(x, y) do
    fbm(x * 0.014, y * 0.13, 4, @cw * 0.014) -
      0.3 * (1 - smooth(@c0, @c0 + 10, y) * smooth(@c1, @c1 - 8, y))
  end

  # A few faint stars in the indigo.
  defp stars(cells) do
    for i <- 0..399,
        x = floor(Hash.scene(i, 91) * @w),
        r = floor(Hash.scene(i, 92) * 40),
        k = r * @w + x,
        elem(elem(elem(cells, k), 0), 0) == @sky and Hash.scene(i, 93) > 0.72,
        do: {k, Hash.scene(i, 94) * 6.28, 0.6 + Hash.scene(i, 95) * 1.6}
  end

  # Petals: each with its own drift, fall, sway and tumble; most of them near
  # the tree, thinning out downwind.
  defp petals do
    for i <- 0..49 do
      {:math.pow(Hash.scene(i, 101), 2.2) * 140, Hash.scene(i, 102) * (@h + 20),
       3 + Hash.scene(i, 103) * 4, 1.6 + Hash.scene(i, 104) * 2.2, 1 + Hash.scene(i, 105) * 2,
       0.6 + Hash.scene(i, 106) * 1.2, Hash.scene(i, 107) * 6.28, 2 + Hash.scene(i, 108) * 4}
    end
  end

  # Petals afloat on the pond, drifting slowly.
  defp floaters do
    for i <- 0..25,
        do:
          {Hash.scene(i, 111) * @w, @shore + 3 + Hash.scene(i, 112) * 20,
           0.3 + Hash.scene(i, 113) * 0.5}
  end

  # The moon: a thin crescent, lit on the side toward the set sun.
  defp moon do
    for r <- (@moon_y - 6)..(@moon_y + 6),
        x <- (@moon_x - 6)..(@moon_x + 6),
        dx = x + 0.5 - @moon_x,
        dy = r + 0.5 - @moon_y,
        dx * dx + dy * dy < 5.2 * 5.2,
        # The shadowed disc, offset up and right.
        (dx - 2.2) * (dx - 2.2) + (dy + 1.6) * (dy + 1.6) > 4.9 * 4.9,
        do: r * @w + x
  end

  # --- the frame ---------------------------------------------------------------

  @impl true
  def frame(state, t, env) do
    # The flame breathes, with now and then a gutter.
    flick =
      0.82 + 0.1 * :math.sin(t * 7.3) * :math.sin(t * 3.1 + 1) +
        0.12 * (noise(t * 4, 3.3, 0) - 0.5) * 2

    fr = %{
      t: t,
      flick: flick,
      cdrift: :math.fmod(:math.fmod(t * 0.8, 1.0 * @cw) + @cw, 1.0 * @cw),
      color?: env.color?,
      cover: state.cover,
      mirror: state.mirror,
      tone: state.tone,
      peaks: state.peaks,
      cols: column_waves(t),
      t2: t * 2,
      t02: t * 0.2,
      t08: t * 0.8
    }

    petals = petals(state, fr)

    {memo, lut} =
      state.rows
      |> Enum.zip(if state.exact?, do: fresh_memo(), else: state.memo)
      |> Enum.map_reduce(state.lut, fn {{r, consts, specs}, memo}, lut ->
        row(specs, memo, 0, {r, consts, Map.get(petals, r), fr}, lut, [])
      end)

    {overlay, lut} = overlay(state, t, env.color?, lut)

    rows =
      memo
      |> Enum.with_index()
      |> Enum.map(fn {cells, r} -> overlaid(cells, 0, Map.get(overlay, r)) end)

    text = Enum.map(rows, &chars/1)
    colors = if env.color?, do: rows |> Enum.map(&colours/1) |> IO.iodata_to_binary()
    {Enum.intersperse(text, ?\n), colors, %{state | lut: lut, memo: memo}}
  end

  defp overlaid(cells, _x, nil), do: cells
  defp overlaid([], _x, _marks), do: []

  defp overlaid([cell | cells], x, marks) do
    case marks do
      %{^x => {char, colour}} -> [{:mark, char, colour} | overlaid(cells, x + 1, marks)]
      _ -> [cell | overlaid(cells, x + 1, marks)]
    end
  end

  defp chars([]), do: []
  defp chars([{_tri, char, _colour} | cells]), do: [char | chars(cells)]

  defp colours([]), do: []
  defp colours([{_tri, _char, colour} | cells]), do: [colour | colours(cells)]

  defp column_waves(t) do
    t06 = t * 0.6
    List.to_tuple(for x <- 0..(@w - 1), do: :math.sin(x * 0.13 + t06) * 1.4)
  end

  # The petals in the air this frame, by row and column: {r, g, b}.
  defp petals(state, fr) do
    t = fr.t

    Enum.reduce(state.petals, %{}, fn {px, py, vx, vy, sw, sf, ph, tum}, acc ->
      xx = wrap(px + vx * t + sw * :math.sin(t * sf + ph), @w, 40) - 20
      yy = wrap(py + vy * t + 0.6 * :math.sin(t * sf * 1.7 + ph), @h, 20) - 10
      x = JSMath.round(xx)
      r = JSMath.round(yy)

      if x < 0 or x >= @w or r < 0 or r >= @h do
        acc
      else
        {m, glow} = elem(state.mat, r * @w + x)
        # Tumbling, catching light; dim against the dark bank and water.
        face =
          (0.55 + 0.45 * abs(:math.sin(t * tum + ph))) *
            if(m == @pond or m == @bank, do: 0.6, else: 1)

        lg = glow * fr.flick * 1.6

        petal =
          {f32(1.0 * face + lg * 0.6), f32(0.76 * face + lg * 0.35), f32(0.84 * face + lg * 0.1)}

        Map.update(acc, r, %{x => petal}, &Map.put(&1, x, petal))
      end
    end)
  end

  # `((((v % (n + m)) + n + m) % (n + m))`, added up as JS adds it.
  defp wrap(v, n, m) do
    span = 1.0 * (n + m)
    :math.fmod(:math.fmod(v, span) + n + m, span)
  end

  # Each cell gives {its tone steps, its dot, its colour}, which the next frame
  # keeps as a memo: a cell whose steps have not moved draws the same dot, and
  # (its colour already in the cache) the same colour.
  defp row([], [], _x, _ctx, lut, acc), do: {Enum.reverse(acc), lut}

  defp row([spec | specs], [memo | memos], x, ctx, lut, acc) do
    {cell, lut} = cell(spec, memo, x, ctx, lut)
    row(specs, memos, x + 1, ctx, lut, [cell | acc])
  end

  defp cell(spec, memo, x, {_r, _consts, nil, _fr} = ctx, lut), do: shade(spec, memo, x, ctx, lut)

  defp cell(spec, memo, x, {_r, consts, petals, fr} = ctx, lut) do
    case Map.get(petals, x) do
      # A petal over the cell: its colour, with a floor of its own.
      {pr, pg, pb} when elem(spec, 0) != :flame ->
        fade = if elem(spec, 0) == :pond, do: elem(consts, 6), else: 1.0
        dot({index(pr), index(pg), index(pb)}, :petal, 0.3, fade, elem(spec, 1), fr, lut)

      _ ->
        shade(spec, memo, x, ctx, lut)
    end
  end

  defp shade({:still, _dith, char, {r, g, b}}, memo, _x, {_, _, _, fr}, lut) do
    case memo do
      {:still, _, colour} when colour != nil or not fr.color? ->
        {memo, lut}

      _ when fr.color? ->
        {i, lut} = Palette.nearest(lut, r, g, b)
        {{:still, char, i}, lut}

      _ ->
        {{:still, char, nil}, lut}
    end
  end

  defp shade({:sky, dith, fl, cr, cg, cb, glow}, memo, _x, {_, _, _, fr}, lut) do
    cr |> lamplit(cg, cb, glow, fr.flick, 0.6) |> dot(memo, fl, 1.0, dith, fr, lut)
  end

  defp shade({:warm, dith, fl, cr, cg, cb, glow, wm}, memo, _x, {_, _, _, fr}, lut) do
    cr |> warm(cg, cb, glow, fr.flick, wm) |> dot(memo, fl, 1.0, dith, fr, lut)
  end

  defp shade({:flame, dith, fl}, memo, _x, {_, _, _, fr}, lut) do
    fr.flick |> flame() |> dot(memo, fl, 1.0, dith, fr, lut)
  end

  defp shade({:cloud, dith, fl, cr, cg, cb, glow, col_sun}, memo, x, {r, sun, _, fr}, lut) do
    {cover, lit} = elem(fr.cover, r - @c0)
    sx = x + fr.cdrift
    ix = floor(sx)
    fx = sx - ix
    i0 = rem(ix, @cw)
    i1 = rem(ix + 1, @cw)
    c = lerp(elem(cover, i0), elem(cover, i1), fx)

    {cr, cg, cb} =
      if c > 0.01,
        do: cloud({cr, cg, cb}, c, lerp(elem(lit, i0), elem(lit, i1), fx), sun, col_sun),
        else: {cr, cg, cb}

    cr |> lamplit(cg, cb, glow, fr.flick, 0.6) |> dot(memo, fl, 1.0, dith, fr, lut)
  end

  # The far side, upside down, shaken by small ripples.
  defp shade({:pond, dith, fl, x014, streak, glow}, memo, x, {_, consts, _, fr}, lut) do
    {depth, y17, wobble, y11, source, lit, fade} = consts
    wob = :math.sin(y17 - fr.t2 + elem(fr.cols, x)) * wobble
    sx = (x + wob) |> js_round() |> max(0) |> min(@w - 1)
    w = noise(x014 + fr.t02, y11 - fr.t08, 0)
    # Ripples also tip the image up and down, so level lines break (drawn a
    # little stretched, so the pagoda's lower roofs land in the pond).
    sr = (source + (w - 0.5) * 3 * depth) |> js_round() |> max(0) |> min(@shore - 1)

    {elem(fr.mirror, sr * @w + sx), lit, w, streak, glow, fr.flick}
    |> water()
    |> dot(memo, fl, fade, dith, fr, lut)
  end

  defp lerp(a, b, f) when is_float(a) and is_float(b) and is_float(f), do: a + (b - a) * f

  # Lamplight on the air: `glow * flick * k`, added in the cell's own way.
  defp lamplit(cr, cg, cb, glow, flick, k)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(glow) and
              is_float(flick) do
    g = glow * flick * k
    {index(cr + g), index(cg + g * 0.6), index(cb + g * 0.3)}
  end

  defp warm(cr, cg, cb, glow, flick, wm)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(glow) and
              is_float(flick) and is_float(wm) do
    g = glow * flick * wm
    {index(cr + g * 1.0), index(cg + g * 0.58), index(cb + g * 0.22)}
  end

  defp flame(flick) when is_float(flick) do
    f = 0.85 + 0.25 * flick
    {index(f), index(0.72 * f), index(0.38 * f)}
  end

  # Brighter undersides toward the west and the horizon.
  defp cloud({cr, cg, cb}, c, l, row_sun, col_sun)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(c) and is_float(l) and
              is_float(row_sun) and is_float(col_sun) do
    sun = l * row_sun * col_sun
    a = c * 0.85

    {mix(cr, mix(0.2, 1.0, sun), a), mix(cg, mix(0.12, 0.58, sun), a),
     mix(cb, mix(0.27, 0.5, sun), a)}
  end

  defp water({{rr, rg, rb}, lit, w, streak, glow, flick})
       when is_float(rr) and is_float(rg) and is_float(rb) and is_float(lit) and is_float(w) and
              is_float(streak) and is_float(glow) and is_float(flick) do
    # Crisp and bright right under the bank, darker further out.
    lit = lit * (0.8 + 0.4 * w)
    glint = smooth(0.74, 0.95, w) * 0.06
    # The lantern's light laid on the water as a broken warm streak.
    sl = streak * smooth(0.45, 0.8, w) * 1.0 * flick
    g = glow * flick * 0.6

    {index(rr * lit * 0.9 + glint + sl + g),
     index(rg * lit * 0.92 + glint * 0.8 + sl * 0.62 + g * 0.6),
     index(rb * lit + 0.03 + glint + sl * 0.25 + g * 0.3)}
  end

  defp level(ir, ig, ib, fl, fade, dith, peaks) do
    {_peak, pw} = elem(peaks, ir |> max(ig) |> max(ib))
    level = level_of(pw, fl, fade)
    {step_of(level, dith), level}
  end

  defp level_of(pw, fl, fade) when is_float(pw) and is_float(fl) and is_float(fade),
    do: clamp(fl + (1 - fl) * pw * 1.02) * fade

  defp step_of(level, dith) when is_float(level) and is_float(dith),
    do: max(0, min(3, js_round(level * 3 + dith)))

  # The colour a dot asks for: brightened or dimmed to make up for its size.
  defp want_rgb(ir, ig, ib, step, level, tone, peaks) do
    {peak, _pw} = elem(peaks, ir |> max(ig) |> max(ib))
    s = scale(step, level, peak)
    {tint(elem(tone, ir), s), tint(elem(tone, ig), s), tint(elem(tone, ib), s)}
  end

  defp scale(0, _level, peak) when is_float(peak), do: 0.3 / peak

  defp scale(step, level, peak) when is_float(level) and is_float(peak),
    do: (0.3 + 0.7 * min(1.0, (level + 0.06) / elem(@cover, step))) / peak

  defp tint(v, s) when is_float(v) and is_float(s), do: clamp(v * s)

  # Tone steps, floor, fade and dither make the dot; a memo with the same
  # steps already has it.
  defp dot(tri, memo, fl, fade, dith, fr, lut) do
    color? = fr.color?

    case memo do
      {^tri, _char, colour} when colour != nil or not color? ->
        {memo, lut}

      _ ->
        {ir, ig, ib} = tri
        {step, level} = level(ir, ig, ib, fl, fade, dith, fr.peaks)
        tri = if memo == :petal, do: :petal, else: tri

        if color? do
          {r, g, b} = want_rgb(ir, ig, ib, step, level, fr.tone, fr.peaks)
          {i, lut} = Palette.nearest(lut, r, g, b)
          {{tri, elem(@dots, step), i}, lut}
        else
          {{tri, elem(@dots, step), nil}, lut}
        end
    end
  end

  # The moon, the stars that twinkle and the petals resting on the pond, drawn
  # over the shading, by row and column.
  defp overlay(state, t, color?, lut) do
    {moon, lut} = mark(state.moon, "●", {1, 0.96, 0.86}, color?, %{}, lut)

    stars =
      for {k, ph, sp} <- state.stars,
          s = :math.sin(t * sp + ph),
          s > -0.3,
          do: {k, if(s > 0.7, do: "•", else: "·")}

    {marks, lut} = marks(stars, {0.9, 0.88, 1}, color?, moon, lut)

    floaters =
      for {fx, fy, sp} <- state.floaters,
          x = JSMath.round(:math.fmod(fx + t * sp, 1.0 * @w)),
          r = JSMath.round(fy + 0.3 * :math.sin(t * 0.8 + fx)),
          r < @h,
          k = r * @w + x,
          k < @w * @h and elem(elem(state.mat, k), 0) == @pond,
          do: {k, "•"}

    marks(floaters, {0.95, 0.72, 0.8}, color?, marks, lut)
  end

  defp mark(ks, char, rgb, color?, marks, lut),
    do: marks(Enum.map(ks, &{&1, char}), rgb, color?, marks, lut)

  defp marks([], _rgb, _color?, marks, lut), do: {marks, lut}

  defp marks(cells, {r, g, b}, color?, marks, lut) do
    {i, lut} = if color?, do: Palette.nearest(lut, r, g, b), else: {0, lut}

    marks =
      Enum.reduce(cells, marks, fn {k, char}, marks ->
        cell = {char, i}
        Map.update(marks, div(k, @w), %{rem(k, @w) => cell}, &Map.put(&1, rem(k, @w), cell))
      end)

    {marks, lut}
  end
end
