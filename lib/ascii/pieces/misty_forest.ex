defmodule Ascii.Pieces.MistyForest do
  @moduledoc """
  Pine ridges fading into morning fog, sunbeams slanting through.

  Morning in a pine forest. Ridge after ridge of pines recedes into fog, each
  paler than the one in front, with mist lying in sheets in the valleys
  between them. A low sun sits behind the farthest trees and sends beams
  slanting down through the fog to a clearing on the forest floor. The fog
  drifts, the beams shimmer, and motes of dust float in the light.

  Every cell is shaded in colour, layer by layer with the haze of its depth,
  then drawn as a halftone: dot size from brightness with an ordered dither,
  colour from the palette entry nearest its hue.

  Ported from `src/pieces/misty-forest.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Hash, Palette, Scene}
  import Bitwise

  @meta %Ascii.Meta{
    name: "misty forest",
    category: :scenes,
    note: "pine ridges fading into morning fog, sunbeams slanting through",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#090f0e",
    palette: [
      # sunlight and the warm fog around it
      "#fffbea",
      "#fff0c8",
      "#fbe2a6",
      "#f2c97e",
      "#e0a95e",
      "#b9834a",
      # cool fog, pale to sea-green
      "#e4ebe6",
      "#cbe0dc",
      "#a8d2d0",
      "#86c0c2",
      "#68a7ac",
      "#4f8c93",
      "#3b7078",
      # pines, from the haze to the dark in front of us
      "#557570",
      "#456761",
      "#365952",
      "#2a4a44",
      "#1f3c37",
      "#172f2b",
      "#11231f",
      # moss and bark where the light touches the floor
      "#a4a35a",
      "#8a8f4c",
      "#6d7440",
      "#4d5530",
      "#7a5a3a",
      "#5b4532",
      # the clear sky above the fog, deepening overhead
      "#a9c3cc",
      "#8eadb8",
      "#6f93a2",
      "#53798a",
      "#3d6172",
      "#2b4a5a"
    ]
  }

  @w 200
  @h 100
  @sun_x 146
  @sun_y 45.5
  @sun_r 3.4
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()
  @sky -1
  @floor 5
  @giant 6

  # The ridges, far to near: {ridge row, its rise and fall, tree spacing, tree
  # heights from and to, haze, how fast its fog drifts, mist lying in the
  # valley below it, drifting fog in front of it, sunbeam in front of it}.
  @layers [
    {50, 6, 1.6, 1, 2.5, 0.48, 0.8, 1, 0.14, 0.6},
    {59, 6, 2, 3, 5.5, 0.3, 1.3, 0.8, 0.16, 0.8},
    {69, 7, 2.6, 4, 7, 0.13, 2, 0.66, 0.18, 0.9},
    {80, 6, 3.4, 5, 9, 0.03, 2.8, 0.44, 0.14, 1},
    {90, 1.5, 10, 9, 24, 0.03, 3.4, 0, 0.08, 0.6}
  ]
  @near 4

  # What stands in front: a giant pine cut by the left of the frame, and a
  # smaller one at the right edge, {x, tip, spread, tier}.
  @giants [{9, -12, 15, 7}, {192, 12, 7, 5}]

  # Drifting fog banks and high cloud wrap every FW columns; the cloud's rows.
  @fw 400
  @ch 46
  # Sunbeams by angle round the sun, RA bins to the turn: {angle, half width,
  # strength}.
  @ra 720
  @shafts [
    {1.42, 0.05, 0.7},
    {1.66, 0.07, 1},
    {1.93, 0.05, 0.8},
    {2.18, 0.08, 1},
    {2.45, 0.05, 0.75},
    {2.7, 0.06, 0.9},
    {2.95, 0.04, 0.6}
  ]

  # The dot's power is bounded from a table below POW_TOP, GRAIN steps a unit.
  @grain 1024
  @pow_top 4

  @impl true
  def meta, do: @meta

  # Called for nearly every cell: local, so they inline.
  @compile {:inline,
            clamp: 1, smooth: 3, mix: 3, js_round: 1, lerp: 3, level: 2, step: 2, want: 2}

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

  defdelegate noise(x, y, period), to: Scene
  defdelegate fbm(x, y, octaves, period), to: Scene

  # The colour of the fog: cool and green-grey, warming to cream by the sun.
  defp fog_r(s), do: mix(0.7, 1.05, s)
  defp fog_g(s), do: mix(0.92, 0.92, s)
  defp fog_b(s), do: mix(0.9, 0.6, s)

  # --- the layers, rasterised far to near so nearer ones cover farther -------

  defp ridge(x, i, {y0, amp, _gap, _h0, _h1, _haze, _speed, _m, _drift, _beam}) do
    # Nearer ridges dip toward the sun, a valley opening onto the light.
    y0 + amp * (fbm(x * (0.018 + i * 0.003), i * 13 + 2, 3, 0) - 0.5) * if(i < 3, do: 4, else: 3) +
      if i > 0 and i < @near,
        do: (2 + i * 2) * :math.exp(-sq((x - @sun_x - 4) / 38)),
        else: 0
  end

  # The cells of every layer: {layer, rim, rows below the tree line, the row
  # its ridge rises from, the lower edge of a tier of boughs}.
  defp layers do
    @layers
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {layer, i}, cells -> rasterise(layer, i, cells) end)
  end

  defp rasterise(layer, i, cells) do
    base = List.to_tuple(for x <- 0..(@w - 1), do: f32(ridge(x, i, layer)))
    starts = List.to_tuple(for x <- 0..(@w - 1), do: max(0, floor(ridge(x, i, layer))))
    {spire, tex} = pines(layer, i)
    fill? = fn x, r -> r >= elem(starts, x) or Map.has_key?(spire, r * @w + x) end

    # Where the silhouette starts in each column, smoothed a little so the
    # mist line follows the forest rather than every single spire.
    top =
      List.to_tuple(for x <- 0..(@w - 1), do: Enum.find(0..(@h - 1), @h, &fill?.(x, &1)))

    line =
      List.to_tuple(
        for x <- 0..(@w - 1) do
          s = Enum.reduce(-3..3, 0, fn d, s -> s + elem(top, min(@w - 1, max(0, x + d))) end)
          f32(max(s / 7, elem(top, x)))
        end
      )

    open? = fn xx, rr -> xx >= 0 and xx < @w and (rr < 0 or not fill?.(xx, rr)) end

    for r <- 0..(@h - 1), x <- 0..(@w - 1), fill?.(x, r), reduce: cells do
      cells ->
        k = r * @w + x
        spire? = Map.has_key?(spire, k)
        # A rim where the sky (or a farther layer) shows beside or above.
        toward = if x < @sun_x, do: 1, else: -1

        edge =
          cond do
            open?.(x + toward, r) or open?.(x, r - 1) -> 1.0
            open?.(x + 2 * toward, r) -> 0.5
            true -> 0.0
          end

        tex = if i == @near, do: Map.get(tex, k, 0.0), else: 0.0

        Map.put(
          cells,
          k,
          {if(i == @near and not spire?, do: @floor, else: i), edge, f32(r + 0.5 - elem(line, x)),
           elem(base, x), tex}
        )
    end
  end

  # Pines: a spire of tiers, each tier flaring out and stepping back in. The
  # cells they cover, and (nearest only) the lower edges of their tiers.
  defp pines({_y0, _amp, gap, h0, h1, _haze, _speed, _m, _drift, _beam} = layer, i) do
    -2
    |> Kernel.+(Hash.scene(i, 1) * gap)
    |> Stream.iterate(&(&1 + gap * (0.7 + Hash.scene(&1, i + 3) * 0.7)))
    |> Enum.take_while(&(&1 < @w + 2))
    # The nearest trees leave a clearing under the sun for the light to land in.
    |> Enum.reject(&(i == @near and &1 > 92 and &1 < 140))
    |> Enum.reduce({%{}, %{}}, fn tx, acc ->
      th = h0 + (h1 - h0) * Hash.scene(tx * 7, i + 5)
      foot = ridge(tx, i, layer)
      tip = foot - th
      tier = 2 + th * 0.12

      for r <- max(0, floor(tip))..(@h - 1)//1,
          r < foot + 2,
          d = r + 0.5 - tip,
          d >= 0,
          saw = :math.fmod(d, tier) / tier,
          half = d * 0.3 * (0.6 + 0.5 * saw) + 0.35,
          x <- max(0, floor(tx - half))..min(@w - 1, ceil(tx + half))//1,
          dx = abs(x + 0.5 - tx),
          dx <= half,
          reduce: acc do
        {spire, tex} ->
          k = r * @w + x

          tex =
            if i == @near,
              do:
                Map.put(
                  tex,
                  k,
                  f32(
                    smooth(0.62, 0.95, saw) * smooth(0.3, 0.85, dx / half) *
                      (0.55 + 0.45 * Hash.scene(x, r * 5))
                  )
                ),
              else: tex

          {Map.put(spire, k, true), tex}
      end
    end)
  end

  # The giant pines: each tier of boughs sweeps out and droops, so the outline
  # is a stack of points rather than a straight edge where it meets the frame.
  defp giants do
    for {gx, tip, spread, tier} <- @giants,
        r <- max(0, floor(tip))..(@h - 1)//1,
        d = r + 0.5 - tip,
        saw = :math.fmod(d, tier) / tier,
        half = min(spread * (0.5 + 0.5 * saw), d * 0.34 * (0.45 + 0.7 * saw) + 0.5),
        x <- max(0, floor(gx - half))..min(@w - 1, ceil(gx + half))//1,
        dx = abs(x + 0.5 - gx),
        # The side toward the frame stays full, so no sliver of sky shows there.
        outer = if((x + 0.5 - gx) * (gx - @w / 2) > 0, do: 1.6, else: 1),
        ragged = half * outer * (0.82 + 0.3 * noise(x * 0.5, r * 0.4, 0)),
        dx <= ragged or dx < 0.9,
        reduce: %{} do
      giant ->
        Map.put(
          giant,
          r * @w + x,
          f32(
            smooth(0.66, 0.96, saw) * smooth(0.25, 0.8, dx / ragged) *
              (0.5 + 0.5 * Hash.scene(x * 3, r))
          )
        )
    end
  end

  # The giants over the layers, with a rim two cells deep on the side that
  # faces the sun.
  defp cover_giants(cells, giant) do
    open? = fn x, r -> x >= 0 and x < @w and (r < 0 or not Map.has_key?(giant, r * @w + x)) end

    Enum.reduce(giant, cells, fn {k, tex}, cells ->
      {x, r} = {rem(k, @w), div(k, @w)}
      tx = if x < @sun_x, do: 1, else: -1

      edge =
        cond do
          open?.(x + tx, r) or open?.(x, r - 1) -> 1.0
          open?.(x + 2 * tx, r) -> f32(0.6)
          true -> 0.0
        end

      {_, _, _, ground, _} = Map.get(cells, k, {@sky, 0.0, 0.0, 0.0, 0.0})
      Map.put(cells, k, {@giant, edge, 0.0, ground, tex})
    end)
  end

  # --- still colour ------------------------------------------------------------

  # Everything about a cell that does not move: {r, g, b, fog, its speed,
  # cloud, beam, floor lit, lift, angle bin, distance and nearness to the sun}.
  defp still(x, r, {l, edge, below, ground, tex}) do
    y = r + 0.5
    dx = x + 0.5 - @sun_x
    dy = y - @sun_y
    ang = :math.atan2(dy, dx)
    d = :math.sqrt(dx * dx + dy * dy)
    s = :math.exp(-:math.sqrt(dx * dx + dy * dy * 1.96) / 30)
    # A soft warm bloom over a wide radius, in the air and the fog.
    bloom = :math.exp(-d / 16) * 0.25 + :math.exp(-d / 6) * 0.1

    {cr, cg, cb, fog, speed, cloud, ray, floor_lit, lift} =
      case l do
        @sky -> sky(x, y, s, d, bloom)
        @near -> near(edge, tex, s)
        @floor -> forest_floor(x, r, y)
        @giant -> giant(edge, tex, d)
        _ -> ridge_colour(x, y, l, edge, below, ground, s, bloom)
      end

    # The beams fan out mostly down and to the west, the way the gaps face.
    ray = ray * (0.2 + 0.8 * smooth(1.25, 1.75, ang) * smooth(3.1, 2.6, ang))

    {f32(cr), f32(cg), f32(cb), f32(fog), f32(speed), f32(cloud), f32(ray), f32(floor_lit),
     f32(lift), f32(:math.fmod(ang / (:math.pi() * 2) * @ra + @ra, 1.0 * @ra)), f32(d), f32(s)}
  end

  # Sky: deep overhead, paling to the fog band low down, warm by the sun.
  defp sky(x, y, s, d, bloom) do
    p = :math.pow(clamp(y / 52), 1.6)
    veil = 0.95 + 0.1 * fbm(x * 0.04, y * 0.08, 3, 0)
    cr = mix(0.065, 0.36, p) * veil
    cg = mix(0.14, 0.58, p) * veil
    cb = mix(0.17, 0.62, p) * veil
    # The fog band the far ridge stands in.
    band = 0.75 * smooth(28, 50, y) * (0.55 + 0.75 * fbm(x * 0.025, y * 0.16, 3, 0))
    cr = mix(cr, fog_r(0), band)
    cg = mix(cg, fog_g(0), band)
    cb = mix(cb, fog_b(0), band)
    # Warm in hue round the sun, but falling off in brightness, so the disc
    # stands in a halo rather than a flat blaze.
    kw = s * 0.55
    kb = 0.5 + 0.5 * :math.exp(-d / 9)
    cr = mix(cr, fog_r(s) * kb, kw)
    cg = mix(cg, fog_g(s) * kb, kw)
    cb = mix(cb, fog_b(s) * kb, kw)
    glow = :math.exp(-d / 3) * 0.3 + :math.exp(-d / 10) * 0.18
    cr = cr + (glow + bloom)
    cg = cg + (glow * 0.9 + bloom * 0.78)
    cb = cb + (glow * 0.66 + bloom * 0.45)
    # The disc itself, a little brighter in the middle.
    disc = smooth(@sun_r + 0.6, @sun_r - 0.4, d)

    cloud =
      0.75 * smooth(5, 15, y) * smooth(44, 28, y) * smooth(@sun_r + 2, @sun_r + 8, d)

    {mix(cr, 1.3, disc), mix(cg, 1.24, disc), mix(cb, 1.08, disc), 0.3 * smooth(30, 50, y), 0.4,
     cloud, 0.35 * smooth(26, 46, y), 0, 0.04}
  end

  # Pine: dark teal, paling with distance; mist pooled just under the tree
  # line, and a sheet of it lying along the valley floor below.
  defp ridge_colour(x, y, l, edge, below, ground, s, bloom) do
    {_, _, _, _, _, haze, speed, m, drift, beam} = Enum.at(@layers, l)
    pool = smooth(2.5, 8 + l * 1.5, below) * smooth(20, 11, below)
    # The sheet follows the lie of the land, smoothly, so it never streaks.
    sheet =
      :math.exp(-sq((y - (ground + 5)) / 3)) * (0.75 + 0.5 * fbm(x * 0.035, l * 7.3, 3, 0))

    mist = clamp(max(pool * 0.5, sheet) * m)
    h = clamp(haze + (1 - haze) * mist)
    veil = 0.9 + 0.2 * fbm(x * 0.06, y * 0.12, 3, 0)
    cr = mix(0.02, fog_r(s) * veil, h) + bloom * h
    cg = mix(0.075, fog_g(s) * veil, h) + bloom * 0.78 * h
    cb = mix(0.07, fog_b(s) * veil, h) + bloom * 0.45 * h
    rim = edge * s * (0.2 + 0.6 * (1 - haze))
    # The trees stop most of the light; the beams show in the mist between
    # (far off there is more air in front of them to hold the light).
    ray =
      beam *
        if l < 3, do: 0.45 + 0.55 * clamp(mist / m), else: 0.25 + 0.75 * clamp(mist / m)

    {cr + rim * 0.95, cg + rim * 0.8, cb + rim * 0.45, drift, speed, 0, ray, 0, 0.03}
  end

  # The nearest pines: near-black, a faint teal on each tier's lower edge (the
  # body itself stays black, or the dither would screen it evenly).
  defp near(edge, tex, s) do
    g = tex * 0.12
    rim = edge * (0.12 + 0.6 * s)
    {_, _, _, _, _, _, speed, _, drift, _} = Enum.at(@layers, @near)

    {0.001 + g * 0.35 + rim * 0.9, 0.004 + g + rim * 0.7, 0.004 + g * 0.9 + rim * 0.38, drift,
     speed, 0, 0.12, 0, 0}
  end

  # The forest floor: moss in clumps, sparse, fading out toward the frame.
  defp forest_floor(x, r, y) do
    clump = smooth(0.42, 0.72, fbm(x * 0.09, y * 0.4, 3, 0))
    speck = if Hash.scene(x * 7, r * 11) > 0.55, do: 1, else: 0.35
    m = (0.06 + 0.3 * clump) * speck * smooth(@h + 2, @h - 8, y)
    # Dappled patches the beams can land on.
    lit = smooth(0.32, 0.56, fbm(x * 0.06 + 3, y * 0.24, 3, 0)) * smooth(@h + 3, @h - 6, y)
    {0.02 + m * 0.6, 0.03 + m * 0.62, 0.02 + m * 0.3, 0.06, 3.4, 0, 0, lit, 0}
  end

  # The giants: near-black needles, the tiers drawn by a faint teal edge, a
  # warm rim two cells deep toward the light, a cool fog-lit edge far from it.
  defp giant(edge, tex, d) do
    g = tex * 0.15
    warm = :math.exp(-d / 50)
    rim = edge * (0.13 + 0.55 * warm)

    {0.001 + g * 0.35 + rim * mix(0.4, 0.95, warm), 0.004 + g + rim * mix(0.75, 0.66, warm),
     0.004 + g * 0.9 + rim * mix(0.72, 0.32, warm), 0.04, 4, 0, 0.04, 0, 0}
  end

  # --- init --------------------------------------------------------------------

  @impl true
  def init(_options) do
    cells = cover_giants(layers(), giants())

    stills =
      for r <- 0..(@h - 1), x <- 0..(@w - 1) do
        still(x, r, Map.get(cells, r * @w + x, {@sky, 0.0, 0.0, 0.0, 0.0}))
      end

    {ray_a, ray_b} = beams()

    %{
      lut: Palette.nearest_lut(@meta.palette),
      rows: rows(stills),
      # For the motes: each cell's angle bin, distance from the sun and beam.
      geo:
        stills
        |> Enum.map(fn {_, _, _, _, _, _, ray, _, _, abin, d, _} -> {abin, d, ray} end)
        |> List.to_tuple(),
      fog: fog(),
      cloud: cloud(),
      ray_a: ray_a,
      ray_b: ray_b,
      motes:
        for(
          i <- 0..109,
          do:
            {Hash.scene(i, 1) * @w, 50 + Hash.scene(i, 2) * 44, 0.3 + Hash.scene(i, 3) * 0.8,
             Hash.scene(i, 4) * 6.28, Hash.scene(i, 5)}
        ),
      memo: fresh_memo(),
      bounds: pow_bounds(),
      # Tests turn the fast paths off (the memo and the power's bounds) to
      # check that frames come out the same without them.
      exact?: false
    }
  end

  defp fresh_memo, do: List.duplicate(List.duplicate(:none, @w), @h)

  # Each cell as the frame shades it, row by row: {r, g, b, fog, cloud, beam,
  # lift}, the moving parts nil where they are too faint to show.
  defp rows(stills) do
    stills
    |> Enum.map(fn {cr, cg, cb, fa, speed, ca, ra, fl, lift, abin, d, s} ->
      fog = if fa > 0.01, do: {fa, speed, fog_r(s), fog_g(s), fog_b(s)}

      cloud =
        if ca > 0.01 do
          # Cool grey-teal, warming to gold on the undersides near the sun.
          w = :math.exp(-d / 40)
          {ca, mix(0.26, 0.95, w), mix(0.38, 0.72, w), mix(0.42, 0.45, w)}
        end

      # Lit shafts brighten the air, the shadows between them dim it.
      shaft = if ra > 0.01 and d > @sun_r, do: {ra, :math.exp(-d / 80) * smooth(@sun_r, 12, d)}
      patch = if fl > 0.01, do: fl
      beam = if ra > 0.01 or fl > 0.01, do: {abin, shaft, patch}
      {cr, cg, cb, fog, cloud, beam, lift}
    end)
    |> Enum.chunk_every(@w)
  end

  # Drifting fog banks: wide soft noise that wraps so it can slide forever.
  defp fog do
    for r <- 0..(@h - 1) do
      List.to_tuple(
        for u <- 0..(@fw - 1),
            do: f32(smooth(0.42, 0.75, fbm(u * 0.022, r * 0.09, 4, @fw * 0.022)))
      )
    end
    |> List.to_tuple()
  end

  # Thin high cloud, long and flat, lit from below by the low sun.
  defp cloud do
    for r <- 0..(@ch - 1) do
      List.to_tuple(
        for u <- 0..(@fw - 1) do
          q = fbm(u * 0.01, r * 0.05, 2, @fw * 0.01)
          f32(smooth(0.44, 0.68, fbm(u * 0.016 + q * 1.5, r * 0.17, 4, @fw * 0.016)))
        end
      )
    end
    |> List.to_tuple()
  end

  # Sunbeams: a handful of wide shafts through the gaps, with a faint grain
  # along each, and a slower pattern sliding across them so they brighten and
  # fade.
  defp beams do
    {a, b} =
      Enum.unzip(
        for i <- 0..(@ra - 1) do
          a = i / @ra * :math.pi() * 2

          v =
            Enum.reduce(@shafts, 0, fn {c, w, st}, v ->
              max(v, st * smooth(w, w * 0.35, abs(a - c)))
            end)

          {f32(v * (0.8 + 0.2 * fbm(i * 0.4, 3.1, 2, @ra * 0.4))),
           f32(smooth(0.4, 0.7, fbm(i * 0.03, 8.7, 2, @ra * 0.03)))}
        end
      )

    {List.to_tuple(a), List.to_tuple(b)}
  end

  # Bounds on `Math.pow(peak, 0.9)` for a peak in [i, i + 1) / GRAIN: each
  # end's power, widened by far more than the error of a libm's pow (under an
  # ulp), so the true power of any peak inside lies between them.
  defp pow_bounds do
    List.to_tuple(
      for i <- 0..(@pow_top * @grain - 1) do
        {:math.pow(i / @grain, 0.9) * (1 - 1.0e-12),
         :math.pow((i + 1) / @grain, 0.9) * (1 + 1.0e-12)}
      end
    )
  end

  # --- the frame ---------------------------------------------------------------

  @impl true
  def frame(state, t, env) do
    motes = motes(state.motes, t)
    # The beams hold their places (the gaps in the trees do not move) and only
    # sway a hair; a second, slower pattern drifts across them.
    fr = %{
      t: t,
      t06: t * 0.6,
      shift_a: 2 * :math.sin(t * 0.35),
      shift_b: -t * 1.6,
      pulse: 0.88 + 0.12 * :math.sin(t * 0.7),
      ray_a: state.ray_a,
      ray_b: state.ray_b,
      geo: state.geo,
      color?: env.color?,
      bounds: if(state.exact?, do: nil, else: state.bounds)
    }

    {memo, lut} =
      state.rows
      |> Enum.zip(if state.exact?, do: fresh_memo(), else: state.memo)
      |> Enum.with_index()
      |> Enum.map_reduce(state.lut, fn {{specs, memo}, r}, lut ->
        cloud = if r < @ch, do: elem(state.cloud, r)
        ctx = {r, elem(state.fog, r), cloud, Map.get(motes, r), fr}
        row(specs, memo, 0, ctx, lut, [])
      end)

    text = Enum.map(memo, &chars/1)
    colors = if env.color?, do: memo |> Enum.map(&colours/1) |> IO.iodata_to_binary()
    {Enum.intersperse(text, ?\n), colors, %{state | lut: lut, memo: memo}}
  end

  # Dust in the air, by row and column: the brightness of each mote.
  defp motes(motes, t) do
    Enum.reduce(motes, %{}, fn {mx, my, sp, ph, sz}, acc ->
      x =
        floor(
          :math.fmod(
            :math.fmod(mx + t * sp + 2.5 * :math.sin(t * 0.4 + ph), 1.0 * @w) + @w,
            1.0 * @w
          )
        )

      y = floor(my + 2 * :math.sin(t * 0.3 + ph * 1.7) - :math.fmod(t * sp * 0.2, 6.0))

      if y < 0 or y >= @h do
        acc
      else
        v = f32(0.5 + 0.5 * sz)
        Map.update(acc, y, %{x => v}, &Map.put(&1, x, v))
      end
    end)
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

  defp shade({cr, cg, cb, fog, cloud, beam, lift}, memo, x, ctx, lut) do
    {r, fog_row, cloud_row, motes, fr} = ctx
    # The fog banks drift, nearer ones faster.
    {cr, cg, cb} = if fog, do: fog(cr, cg, cb, fog, fog_row, x, fr.t), else: {cr, cg, cb}

    {cr, cg, cb} =
      if cloud, do: cloud(cr, cg, cb, cloud, cloud_row, x, fr.t06), else: {cr, cg, cb}

    # The beams: brightest near the sun, fading with distance.
    {cr, cg, cb} = if beam, do: beam(cr, cg, cb, beam, fr), else: {cr, cg, cb}

    case motes && Map.get(motes, x) do
      nil -> dot(cr, cg, cb, lift, x, r, memo, fr, lut)
      mote -> mote(cr, cg, cb, lift, mote, x, r, fr, lut)
    end
  end

  defp lerp(a, b, f) when is_float(a) and is_float(b) and is_float(f), do: a + (b - a) * f

  defp fog(cr, cg, cb, {fa, speed, fr, fg, fb}, row, x, t)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(fa) and is_float(speed) and
              is_float(fr) and is_float(fg) and is_float(fb) and is_float(t) do
    u = x + t * speed
    ui = floor(u)
    a = lerp(elem(row, rem(ui, @fw)), elem(row, rem(ui + 1, @fw)), u - ui) * fa
    {mix(cr, fr, a), mix(cg, fg, a), mix(cb, fb, a)}
  end

  defp cloud(cr, cg, cb, {ca, kr, kg, kb}, row, x, t06)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(ca) and is_float(kr) and
              is_float(kg) and is_float(kb) and is_float(t06) do
    u = x + t06
    ui = floor(u)
    a = lerp(elem(row, rem(ui, @fw)), elem(row, rem(ui + 1, @fw)), u - ui) * ca
    if a > 0.005, do: {mix(cr, kr, a), mix(cg, kg, a), mix(cb, kb, a)}, else: {cr, cg, cb}
  end

  defp beam(cr, cg, cb, {abin, shaft, patch}, fr) do
    %{shift_a: shift_a, shift_b: shift_b, pulse: pulse} = fr
    a = elem(fr.ray_a, wrap(floor(abin + shift_a)))
    b = elem(fr.ray_b, wrap(floor(abin + shift_b)))
    beam = beam_strength(a, b, pulse)
    {cr, cg, cb} = if shaft, do: shaft(cr, cg, cb, shaft, beam), else: {cr, cg, cb}
    # A patch of sun on the moss where a beam lands.
    if patch, do: patch(cr, cg, cb, patch, beam), else: {cr, cg, cb}
  end

  defp wrap(i), do: rem(rem(i, @ra) + @ra, @ra)

  defp beam_strength(a, b, pulse) when is_float(a) and is_float(b) and is_float(pulse),
    do: a * (0.6 + 0.4 * b) * pulse

  defp shaft(cr, cg, cb, {ra, fall}, beam)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(ra) and is_float(fall) and
              is_float(beam) do
    b = (beam - 0.3) * fall * ra * 2.2

    if b > 0 do
      {cr + b * 1.05, cg + b * 0.8, cb + b * 0.42}
    else
      dim = 1 + b
      {cr * dim, cg * dim, cb * dim}
    end
  end

  defp patch(cr, cg, cb, fl, beam)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(fl) and is_float(beam) do
    b = beam * fl * 1.1
    {cr + b, cg + b * 0.78, cb + b * 0.4}
  end

  # A mote shows up where a beam catches it.
  defp mote(cr, cg, cb, lift, mote, x, r, fr, lut) do
    {abin, d, ray} = elem(fr.geo, r * @w + x)

    {cr, cg, cb, lift} =
      if d > 6 do
        lit = elem(fr.ray_a, wrap(floor(abin + fr.shift_a))) * :math.exp(-d / 90)
        v = mote * (0.1 + 1.6 * lit) * min(1, ray * 2)

        if v > 0.18,
          do: {max(cr, v * 1.05), max(cg, v * 0.97), max(cb, v * 0.7), 0.3},
          else: {cr, cg, cb, lift}
      else
        {cr, cg, cb, lift}
      end

    dot(cr, cg, cb, lift, x, r, :mote, fr, lut)
  end

  # Dot size from brightness, dithered; the colour makes up what the dot size
  # could not. A memo of the same colour already has both.
  defp dot(cr, cg, cb, fl, x, r, memo, fr, lut)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(fl) do
    color? = fr.color?

    case memo do
      {^cr, ^cg, ^cb, _char, colour} when colour != nil or not color? ->
        {memo, lut}

      _ ->
        peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
        bayer = elem(@bayer, band(r, 3) * 4 + band(x, 3))
        {step, want} = settle(peak, fl, bayer, color?, fr.bounds)

        {i, lut} =
          if color? do
            s = (0.3 + 0.7 * want) / peak
            Palette.nearest(lut, clamp(cr * s), clamp(cg * s), clamp(cb * s))
          else
            {nil, lut}
          end

        # A mote's cell is drawn afresh next frame.
        if memo == :mote,
          do: {{nil, nil, nil, elem(@dots, step), i}, lut},
          else: {{cr, cg, cb, elem(@dots, step), i}, lut}
    end
  end

  defp level(p, fl) when is_float(p) and is_float(fl), do: clamp(fl + (1 - fl) * p * 0.95)

  defp step(level, bayer) when is_float(level) and is_float(bayer),
    do: max(0, min(3, js_round(level * 3 + bayer)))

  defp want(0, _level), do: 0.0
  defp want(step, level) when is_float(level), do: min(1.0, (level + 0.06) / elem(@cover, step))

  # The dot's step and the weight of its colour. Both rise with
  # `Math.pow(peak, 0.9)`, so where they are the same at both ends of that
  # power's bounds (and the weight is 0 or full) they need not wait for it.
  defp settle(peak, fl, bayer, color?, bounds) when is_tuple(bounds) and peak < @pow_top do
    {lo, hi} = elem(bounds, trunc(peak * @grain))
    low = level(lo, fl)
    step = step(low, bayer)

    cond do
      step != step(level(hi, fl), bayer) -> exact(peak, fl, bayer)
      step == 0 -> {0, 0.0}
      not color? -> {step, nil}
      want(step, low) == 1 -> {step, 1.0}
      true -> exact(peak, fl, bayer)
    end
  end

  defp settle(peak, fl, bayer, _color?, _bounds), do: exact(peak, fl, bayer)

  defp exact(peak, fl, bayer) do
    level = level(:math.pow(peak, 0.9), fl)
    step = step(level, bayer)
    {step, want(step, level)}
  end
end
