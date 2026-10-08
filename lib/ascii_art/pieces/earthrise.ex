defmodule AsciiArt.Pieces.Earthrise do
  @moduledoc """
  The earth rising over a cratered lunar horizon in long low sunlight.

  The Earth coming up over the lunar horizon. The sun is low on the right, so
  every crater rim and boulder throws a long black shadow across the grey
  ground, and the same light makes a gibbous Earth with a clean line between
  day and night. The Earth turns, its clouds drift, it climbs very slowly, and
  a few bright stars breathe.

  The ground is a heightfield of craters, rendered once column by column from
  a camera standing on it, with real shadows marched toward the sun. Each
  frame only the Earth and the few stars that twinkle are shaded again. Every
  cell is then drawn as a halftone dot sized by its brightness, ordered-
  dithered, in the palette colour nearest its hue.

  Ported from `src/pieces/earthrise.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Hash, Palette, Scene}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "earthrise",
    category: :scenes,
    note: "the earth rising over a cratered lunar horizon in long low sunlight",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#030408",
    palette: [
      "#18181b",
      "#232326",
      "#303033",
      "#414143",
      "#555556",
      "#6b6a69",
      "#83817d",
      "#9c9993",
      "#b6b2aa",
      "#cfcac1",
      "#e6e1d8",
      "#f7f4ee",
      "#0c1120",
      "#131a2e",
      "#1b2540",
      "#262f4a",
      "#dfe9ff",
      "#0a2259",
      "#0f2f72",
      "#15408c",
      "#1d53a6",
      "#2a69bf",
      "#4386d3",
      "#6eaeea",
      "#a8d3f6",
      "#e8f0fa",
      "#c2d0e3",
      "#8b9fbc",
      "#2f4a26",
      "#3b5a2c",
      "#5b7238",
      "#7a9150",
      "#77783f",
      "#8f8550",
      "#a8955e",
      "#6b5634",
      "#b9774a",
      "#8a4838"
    ]
  }

  @w 200
  @h 100
  # Screen row of eye level; the horizon dips below it.
  @eye 37
  # Focal length in cells.
  @f 112
  @cam_h 20
  # The moon's radius, in ground units, for the falling horizon.
  @rm 1500
  @zmax 520
  # The Earth on screen, its lower edge still behind the horizon.
  @ec_x 141
  @ec_y 32
  @er 22
  # Which face of the globe is turned to us at the start.
  @lon0 3.5
  # It climbs RISE rows and settles back over RISE_T seconds.
  @rise 5
  @rise_t 150
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()
  # The bright stars, which twinkle: {col, row, brightness, period in seconds}.
  @bright [{24, 9, 1, 4.6}, {67, 27, 0.85, 3.4}, {99, 12, 0.95, 5.8}, {189, 7, 0.8, 4.1}]
  # The faint cross each bright star carries: {dx, dy, weight}.
  @cross [{0, 0, 1}, {-1, 0, 0.2}, {1, 0, 0.2}, {0, -1, 0.2}, {0, 1, 0.2}]
  # A few big boulders in the near ground, {x, z, radius}.
  @rocks [
    {30, 50, 2.4},
    {62, 63, 1.8},
    {12, 70, 1.3},
    {-4, 45, 1.2},
    {90, 55, 1.6},
    {46, 90, 1.4}
  ]
  # The storms the clouds wind round: {longitude, latitude, spin}.
  @storms [{0.9, 0.8, 1}, {3.1, -0.85, -1}, {4.6, 0.62, 1}, {1.9, 0.25, 1}, {5.6, -0.55, -1}]
  # The Earth's maps, equirectangular.
  @tw 192
  @th 96
  # The sky cells the Earth and its air can reach, as it rises and settles.
  @box_rows max(0, @ec_y - @rise - @er - 13)..min(@h - 1, @ec_y + @er + 2)
  @box_x0 @ec_x - @er - 13
  @box_x1 @ec_x + @er + 13
  # Past this distance from the Earth's centre the air's rim is below its
  # cut-off (`exp(-3.5 / 1.2) * 0.55 < 0.05`), so a cell keeps its still.
  @reach2 25.5 * 25.5
  # The dot's power is bounded from a table below POW_TOP, GRAIN steps a unit.
  @grain 1024
  @pow_top 4

  @impl true
  def meta, do: @meta

  # Called for nearly every cell: local, so they inline.
  @compile {:inline, clamp: 1, smooth: 3, mix: 3, sq: 1, float!: 1}
  # Floats out, so the shading stays in float arithmetic.
  defp clamp(v) when v < 0, do: 0.0
  defp clamp(v) when v > 1, do: 1.0
  defp clamp(v), do: v

  # A float, as far as the compiler can tell, for what a call returns.
  defp float!(v) when is_float(v), do: v

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  # `v ** 2`, which V8 computes as `v * v`.
  defp sq(v), do: v * v

  defdelegate noise(x, y, period), to: Scene
  defdelegate fbm(x, y, octaves, period), to: Scene

  # --- the ground ------------------------------------------------------------

  # A bowl with a raised rim, r in ground units, q its distance in radii.
  defp bowl(q, r) do
    r * (if(q < 1, do: -0.36 * (1 - q * q), else: 0) + 0.14 * :math.exp(-sq((q - 1) / 0.25)))
  end

  # Craters scattered one to a cell.
  defp craters(x, z, {cell, _salt, _r0, _r1, _p} = field) do
    ci = floor(x / cell)
    cj = floor(z / cell)

    for j <- (cj - 1)..(cj + 1), i <- (ci - 1)..(ci + 1), reduce: 0 do
      h -> crater(h, x, z, i, j, field)
    end
  end

  defp crater(h, x, z, i, j, {cell, salt, r0, r1, p}) do
    if Hash.scene(i + salt, j - salt) > p do
      h
    else
      cx = (i + Hash.scene(i, j + salt * 3)) * cell
      cz = (j + Hash.scene(i + salt * 5, j)) * cell
      e = Hash.scene(j + salt, i - salt * 7)
      r = cell * (r0 + (r1 - r0) * e * e)
      dx = x - cx
      dz = z - cz
      d2 = dx * dx + dz * dz
      if d2 > 4 * r * r, do: h, else: h + bowl(:math.sqrt(d2) / r, r) * 0.95
    end
  end

  defp height(x, z) do
    h = 6 * fbm(x * 0.006 + 50, z * 0.006 + 50, 3, 0) + 0.6 * fbm(x * 0.04, z * 0.04, 2, 0)
    h = if z > 150, do: highlands(h, x, z), else: h
    # Big basins only out in the middle distance, so we do not stand in one.
    h =
      if z > 90,
        do: h + craters(x, z, {110, 11, 0.14, 0.34, 0.55}) * smooth(90, 150, z),
        else: h

    h = if z < 300, do: h + craters(x, z, {34, 23, 0.12, 0.36, 0.85}), else: h

    h =
      if z < 170,
        do: h + craters(x, z, {10, 37, 0.12, 0.34, 0.85}) * smooth(170, 110, z),
        else: h

    # One big crater in the near ground, off to the left.
    dx = x + 24
    dz = z - 58
    q = :math.sqrt(dx * dx + dz * dz) / 16
    h = if q < 2, do: h + bowl(q, 16), else: h
    if z < 90, do: boulders(h, x, z), else: h
  end

  # Old, worn highlands at the edge of sight, rising to the left, and a lower
  # ridge in front of them.
  defp highlands(h, x, z) do
    lift = smooth(150, 300, z)
    # Rounded massifs: folded noise, worn smooth.
    m = 1 - abs(2 * fbm(x * 0.006 + 7, z * 0.006, 4, 0) - 1)
    h = h + lift * (28 * :math.exp(-sq((x + 260) / 230)) + 45 * (m * m - 0.35))
    ridge = :math.exp(-sq((z - 205) / 20)) * :math.exp(-sq((x + 140) / 130))
    h + ridge * 22 * (0.35 + fbm(x * 0.018 + 3, z * 0.01, 3, 0))
  end

  # Boulders strewn close by, and a few big ones.
  defp boulders(h, x, z) do
    ci = floor(x / 5)
    cj = floor(z / 5)

    h =
      if Hash.scene(ci + 91, cj) < 0.14 do
        bx = (ci + 0.2 + 0.6 * Hash.scene(ci, cj + 92)) * 5
        bz = (cj + 0.2 + 0.6 * Hash.scene(ci + 93, cj)) * 5
        br = 0.3 + 0.5 * sq(Hash.scene(ci + 94, cj + 95))
        d2 = (sq(x - bx) + sq(z - bz)) / (br * br)
        if d2 < 4, do: h + br * 0.9 * :math.exp(-d2 * 1.4), else: h
      else
        h
      end

    Enum.reduce(@rocks, h, fn {bx, bz, br}, h ->
      d2 = (sq(x - bx) + sq(z - bz)) / (br * br)
      # A squat, lumpy dome.
      if d2 < 1,
        do: h + br * (0.85 + 0.3 * noise(x * 1.3, z * 1.3, 0)) * :math.sqrt(1 - d2),
        else: h
    end)
  end

  @impl true
  def init(_options) do
    # Toward the sun: low, from the right and a little behind us (z is forward).
    sun = unit([0.94, 0.14, -0.3])
    cam_y = height(0, 7) + @cam_h
    {ground, top} = march_ground(cam_y)

    # Still light: the ground and the sky, everything but the Earth's disc.
    still =
      List.to_tuple(
        for r <- 0..(@h - 1), x <- 0..(@w - 1) do
          case Map.fetch(ground, r * @w + x) do
            {:ok, g} -> ground_light(x, r, g, top, cam_y, sun)
            :error -> sky(x, r)
          end
        end
      )

    {cells, lut} =
      still
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.map_reduce(Palette.nearest_lut(@meta.palette), fn {{cr, cg, cb, cap}, k}, lut ->
        dot({rem(k, @w), div(k, @w)}, {cr, cg, cb}, 0.0, cap, nil, lut)
      end)

    cells = List.to_tuple(cells)
    {cloud, tex} = earth_maps()
    {l0, l1, l2} = {elem(sun, 0), elem(sun, 1), -elem(sun, 2)}
    stars = stars(ground, still)

    %{
      lut: lut,
      bounds: pow_bounds(),
      # Tests turn the fast paths off (the power's bounds, the cells left still
      # round the Earth) to check that frames come out the same without them.
      exact?: false,
      box: box(ground, still, cells),
      stars: stars,
      rows: rows(cells, Map.new(stars, &{elem(&1, 0), true})),
      cloud: cloud,
      tex: tex,
      # Into screen space, z toward us.
      light: {l0, l1, l2},
      half: unit([l0, l1, l2 + 1]),
      tilt: {:math.cos(0.4), :math.sin(0.4), :math.cos(0.22), :math.sin(0.22)}
    }
  end

  defp unit(v) do
    l = JSMath.hypot_list(v)
    v |> Enum.map(&(&1 / l)) |> List.to_tuple()
  end

  # March each column from near to far.
  defp march_ground(cam_y) do
    {tops, cells} =
      Enum.map_reduce(0..(@w - 1), [], fn c, cells ->
        march({c, (c + 0.5 - @w / 2) / @f, cam_y}, 26, @h, {0, 0, 1.0e9}, cells)
      end)

    {Map.new(cells), List.to_tuple(tops)}
  end

  defp march({c, dir, cam_y} = col, z, top_r, prev, cells) when z < @zmax and top_r > 0 do
    x = dir * z
    hy = height(x, z)
    y = hy - z * z / (2 * @rm)
    yf = @eye - @f * (y - cam_y) / z
    r0 = max(0, ceil(yf - 0.5))

    cells =
      Enum.reduce(r0..(top_r - 1)//1, cells, fn r, cells ->
        [{r * @w + c, place(r, dir, z, hy, yf, prev)} | cells]
      end)

    march(col, z + (0.03 + z * 0.012), min(top_r, r0), {hy, z, yf}, cells)
  end

  defp march(_col, _z, top_r, _prev, cells), do: {top_r, cells}

  # Place the cell between this sample and the last, by where its row falls.
  defp place(_r, dir, z, hy, _yf, {_prev_y, 0, _prev_f}) do
    gz = JSMath.fround(z)
    {JSMath.fround(dir * gz), gz, JSMath.fround(hy)}
  end

  defp place(r, dir, z, hy, yf, {prev_y, prev_z, prev_f}) do
    a = if prev_f > yf + 1.0e-6, do: clamp((prev_f - (r + 0.5)) / (prev_f - yf)), else: 1
    gz = JSMath.fround(mix(prev_z, z, a))
    {JSMath.fround(dir * gz), gz, JSMath.fround(mix(prev_y, hy, a))}
  end

  defp ground_light(x, r, {gx, gz, gy}, top, cam_y, {s0, s1, s2} = sun) do
    e = 0.1 + gz * 0.004
    hx = (height(gx + e, gz) - height(gx - e, gz)) / (2 * e)
    hz = (height(gx, gz + e) - height(gx, gz - e)) / (2 * e)
    nl = JSMath.hypot(hx, 1, hz)
    lam = (-hx * s0 + s1 - hz * s2) / nl
    # Toward the eye, for the moon's own way of reflecting (Lommel-Seeliger).
    vx = -gx
    vy = cam_y - gy
    vz = -gz
    vl = JSMath.hypot(vx, vy, vz)
    mu = max(0.02, (-hx * vx + vy - hz * vz) / (nl * vl))
    # March toward the sun; a soft edge for the sun's own width.
    lit = if lam > 0, do: smooth(0, 1, shadow(gx, gy, gz, 0.1 + gz * 0.003, 1, sun)), else: 0
    # Regolith: patchy, the maria darker.
    albedo =
      0.5 + 0.9 * fbm(gx * 0.025 + 3, gz * 0.025, 3, 0) +
        0.3 * (fbm(gx * 0.35, gz * 0.35, 2, 0) - 0.5) -
        0.22 * smooth(0.46, 0.64, fbm(gx * 0.0035, gz * 0.0035 + 20, 3, 0))

    ls = if lam > 0, do: (0.2 * lam / (lam + mu) + 2.6 * lam) * lit, else: 0
    # The near corners fall off a little, to frame the view.
    vig = 1 - 0.3 * smooth(84, 102, r) * smooth(30, 100, abs(x - 100))
    b = :math.pow((1 - :math.exp(-ls * 1.5)) * albedo, 1.0) * vig
    # The far crest catches the sun along its whole length.
    crest = r - elem(top, x)

    b =
      if crest < 2 and lit > 0.2,
        do: max(b, if(crest != 0, do: 0.55, else: 0.85) * albedo),
        else: b

    # Shadow is black, but for a breath of earthshine on what faces us.
    fill = if lit > 0.02 or b > 0.03, do: 0.008 + 0.007 * clamp(-hz / nl + 0.5), else: 0

    {
      JSMath.fround(b * 1.0 + fill * 0.75),
      JSMath.fround(b * 0.95 + fill * 0.85),
      JSMath.fround(b * 0.86 + fill * 1.2),
      # Grey stays grey: dim ground draws in darker ink.
      JSMath.fround(0.42 + 0.62 * b)
    }
  end

  defp shadow(_x, _y, _z, s, lit, _sun) when s >= 120, do: lit

  defp shadow(x, y, z, s, lit, {s0, s1, s2} = sun) do
    d = y + s1 * s - height(x + s0 * s, z + s2 * s)
    if d < 0, do: 0, else: shadow(x, y, z, s + (0.05 + s * 0.2), min(lit, d * 30 / s), sun)
  end

  # A black sky. Faint stars, thicker along a diagonal where the galaxy runs,
  # none round the Earth.
  defp sky(x, r) do
    band_d = (r - (4 + x * 0.32)) / 1.05

    band =
      :math.exp(-sq(band_d / 10)) * smooth(0.35, 0.65, fbm(x * 0.05, r * 0.08, 3, 0)) *
        smooth(120, 70, x)

    if Hash.scene(x * 3 + 1, r * 7 + 2) > 0.994 - 0.05 * band and not near?(x, r) do
      m = :math.pow(Hash.scene(x + 17, r + 29), 3)
      s = 0.2 + 0.5 * m
      tint = Hash.scene(x + 5, r + 77)

      {tr, tg, tb} =
        cond do
          tint < 0.3 -> {0.84, 0.9, 1}
          tint > 0.88 -> {1, 0.93, 0.84}
          true -> {0.96, 0.96, 0.98}
        end

      {JSMath.fround(s * tr), JSMath.fround(s * tg), JSMath.fround(s * tb), 1.0}
    else
      {0.0, 0.0, 0.0, 1.0}
    end
  end

  defp near?(x, r),
    do: JSMath.hypot(x + 0.5 - @ec_x, r + 0.5 - (@ec_y - @rise / 2)) < 2 * @er

  # Halftone one cell: dot size from brightness, colour from hue, with the
  # colour making up what the dot size could not.
  defp dot({x, r}, {cr, cg, cb}, fl, cap, bounds, lut)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(fl) and is_float(cap) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    {step, want} = settle(peak, fl, elem(@bayer, band(r, 3) * 4 + band(x, 3)), bounds)
    s = min(cap, 0.3 + 0.7 * want) / peak
    {index, lut} = Palette.nearest(lut, clamp(cr * s), clamp(cg * s), clamp(cb * s))
    {{elem(@dots, step), index}, lut}
  end

  defp level(p, fl) when is_float(p) and is_float(fl), do: clamp(fl + (1 - fl) * p * 0.95)

  defp step(level, bayer) when is_float(level) and is_float(bayer),
    do: max(0, min(3, JSMath.round(level * 3 + bayer)))

  defp want(0, _level), do: 0.0
  defp want(step, level) when is_float(level), do: min(1.0, (level + 0.06) / elem(@cover, step))

  # The dot's step and the weight of its colour. Both rise with
  # `Math.pow(peak, 0.85)`, so where they are the same at both ends of that
  # power's bounds (and the weight is 0 or full) they need not wait for it.
  defp settle(peak, fl, bayer, bounds) when is_tuple(bounds) and peak < @pow_top do
    {lo, hi} = elem(bounds, trunc(peak * @grain))
    low = level(lo, fl)
    step = step(low, bayer)

    cond do
      step != step(level(hi, fl), bayer) -> exact(peak, fl, bayer)
      step == 0 -> {0, 0.0}
      want(step, low) == 1 -> {step, 1.0}
      true -> exact(peak, fl, bayer)
    end
  end

  defp settle(peak, fl, bayer, _bounds), do: exact(peak, fl, bayer)

  defp exact(peak, fl, bayer) do
    level = level(:math.pow(peak, 0.85), fl)
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

  # --- the Earth ---------------------------------------------------------------

  # Equirectangular maps, wrapping in longitude: surface colour and the sea
  # (one tuple per texel), and cloud.
  defp earth_maps do
    raw = for j <- 0..(@th - 1), i <- 0..(@tw - 1), do: texel_raw(i, j)
    # Thresholds by share of the globe: about three tenths land, a third cloud.
    shore = raw |> Enum.map(&elem(&1, 0)) |> quantile(0.7)
    clouds = Enum.map(raw, &elem(&1, 1))
    c0 = quantile(clouds, 0.6)
    c1 = quantile(clouds, 0.86)

    tex =
      raw
      |> Enum.with_index()
      |> Enum.map(fn {{e, _}, t} -> texel(rem(t, @tw), div(t, @tw), e, shore) end)
      |> List.to_tuple()

    {clouds |> Enum.map(&JSMath.fround(smooth(c0, c1, &1))) |> List.to_tuple(), tex}
  end

  defp quantile(values, p) do
    sorted = Enum.sort(values)
    Enum.at(sorted, floor(p * (length(sorted) - 1)))
  end

  defp texel_raw(i, j) do
    v = (j + 0.5) / @th
    lat = (0.5 - v) * :math.pi()
    al = abs(lat)
    u = i / @tw
    lon = u * :math.pi() * 2
    wx = fbm(u * 6, v * 3 + 9, 3, 6)
    elev = fbm(u * 8 + 1.6 * wx, v * 4, 5, 8) - 0.04 * smooth(1.2, 1.5, al)
    # Clouds: warped noise, wound into spirals around a few storms.
    {cx, cy} = Enum.reduce(@storms, {u * 14, v * 7}, &swirl(&1, &2, lon, lat))
    # Streaked along the winds, east to west.
    q = fbm(cx * 0.5 + 3, cy * 1.2, 3, 7)
    n0 = fbm(cx + 1.6 * q, cy * 1.3 + 0.5 * q, 5, 14)
    # Folded into filaments, the way weather fronts string out.
    n = 0.4 * n0 + 0.6 * (1 - abs(2 * fbm(cx * 1.5 + 2.2 * q, cy * 1.6 + 9, 4, 21) - 1))
    # Cloudy at the equator and in the storm belts, clearer in the subtropics.
    belt =
      0.05 * :math.exp(-sq(lat / 0.12)) - 0.07 * :math.exp(-sq((al - 0.42) / 0.16)) +
        0.05 * :math.exp(-sq((al - 0.95) / 0.25))

    {JSMath.fround(elev), JSMath.fround(n + belt)}
  end

  defp swirl({slon, slat, spin}, {cx, cy}, lon, lat) do
    dl = lon - slon
    dl = dl - JSMath.round(dl / (:math.pi() * 2)) * :math.pi() * 2
    lx = dl * :math.cos(lat)
    ly = lat - slat
    dd = JSMath.hypot(lx, ly)
    a = spin * 5 * :math.exp(-dd / 0.2)

    if a * spin > 0.02 do
      ca = :math.cos(a)
      sa = :math.sin(a)

      {cx + (lx * ca - ly * sa - lx) / (:math.pi() * 2) * 14,
       cy - (lx * sa + ly * ca - ly) / :math.pi() * 7}
    else
      {cx, cy}
    end
  end

  defp texel(i, j, e, shore) do
    v = (j + 0.5) / @th
    al = abs((0.5 - v) * :math.pi())
    u = i / @tw
    land = smooth(shore - 0.004, shore + 0.006, e)
    ice = smooth(1.22, 1.32, al + 0.12 * fbm(u * 12, v * 6, 2, 12))
    # Desert in the subtropics and on high ground, forest and scrub elsewhere,
    # broken up finely so a continent is never one flat tone.
    grain = fbm(u * 36 + 2, v * 18, 3, 36) - 0.5

    arid =
      clamp(
        :math.exp(-sq((al - 0.4) / 0.22)) * (0.1 + 1.2 * fbm(u * 10 + 4, v * 5, 3, 10)) +
          (e - shore - 0.04) * 4 + 0.8 * grain
      )

    relief = 1 + 1.2 * grain - 2.5 * max(0, e - shore - 0.08)
    r = mix(0.13, 0.4, arid) * relief
    g = mix(0.25, 0.34, arid) * relief
    b = mix(0.08, 0.19, arid) * relief
    # Ocean, lighter over the shelves near the coasts.
    shelf = smooth(shore - 0.06, shore, e)
    r = mix(mix(0.025, 0.07, shelf), r, land)
    g = mix(mix(0.11, 0.3, shelf), g, land)
    b = mix(mix(0.38, 0.62, shelf), b, land)

    {JSMath.fround(mix(r, 0.92, ice)), JSMath.fround(mix(g, 0.95, ice)),
     JSMath.fround(mix(b, 0.99, ice)), JSMath.fround((1 - land) * (1 - ice))}
  end

  # The four corners of a map's cell and the weights between them.
  defp corners(lon, vy) when is_float(lon) and is_float(vy) do
    fx = :math.fmod(:math.fmod(lon / (:math.pi() * 2), 1.0) + 1, 1.0) * @tw
    x0 = floor(fx)
    x1 = rem(x0 + 1, @tw)
    y0 = max(0, min(@th - 2, floor(vy)))
    i = y0 * @tw
    {i + x0, i + x1, i + @tw + x0, i + @tw + x1, fx - x0, clamp(vy - y0)}
  end

  defp sample(map, lon, vy) do
    {ia, ib, ic, id, ax, ay} = corners(lon, vy)
    lerp(elem(map, ia), elem(map, ib), elem(map, ic), elem(map, id), ax, ay)
  end

  defp lerp(a, b, c, d, ax, ay)
       when is_float(a) and is_float(b) and is_float(c) and is_float(d) and is_float(ax) and
              is_float(ay),
       do: a + (b - a) * ax + (c - a) * ay + (a - b - c + d) * ax * ay

  # The surface colour and the sea, sampled together.
  defp sample_surface(tex, lon, vy) do
    {ia, ib, ic, id, ax, ay} = corners(lon, vy)
    {ar, ag, ab, as} = elem(tex, ia)
    {br, bg, bb, bs} = elem(tex, ib)
    {cr, cg, cb, cs} = elem(tex, ic)
    {dr, dg, db, ds} = elem(tex, id)

    {lerp(ar, br, cr, dr, ax, ay), lerp(ag, bg, cg, dg, ax, ay), lerp(ab, bb, cb, db, ax, ay),
     lerp(as, bs, cs, ds, ax, ay)}
  end

  # --- what the frame redraws ------------------------------------------------

  # The box round the Earth, row by row: each sky cell with its still light,
  # each cell with what it draws when still.
  defp box(ground, still, cells) do
    for r <- @box_rows do
      for x <- @box_x0..@box_x1 do
        k = r * @w + x

        if Map.has_key?(ground, k) do
          {:still, elem(cells, k)}
        else
          {sr, sg, sb, scap} = elem(still, k)
          {x, x + 0.5 - @ec_x, sr, sg, sb, scap, elem(cells, k)}
        end
      end
      |> then(&{r, r + 0.5, &1})
    end
  end

  # The bright stars and the faint cross each one carries.
  defp stars(ground, still) do
    for {x, r, s, p} <- @bright,
        {ox, oy, w} <- @cross,
        k = (r + oy) * @w + x + ox,
        not Map.has_key?(ground, k) do
      {sr, sg, sb, _} = elem(still, k)
      {k, x + ox, r + oy, s * w, p, Hash.scene(x, r) * 6.28, w == 1, {sr, sg, sb}}
    end
  end

  # Each row as runs of still cells, the box's place, and the stars' cells.
  defp rows(cells, star?) do
    for r <- 0..(@h - 1) do
      0..(@w - 1)
      |> Enum.map(fn x ->
        k = r * @w + x

        cond do
          r in @box_rows and x in @box_x0..@box_x1 -> :box
          Map.has_key?(star?, k) -> {:star, k}
          true -> {:still, elem(cells, k)}
        end
      end)
      |> Enum.chunk_by(fn
        {:still, _} -> :still
        other -> other
      end)
      |> Enum.map(fn
        [{:still, _} | _] = run ->
          {run |> Enum.map(fn {:still, {c, _}} -> c end) |> IO.iodata_to_binary(),
           run |> Enum.map(fn {:still, {_, i}} -> i end) |> IO.iodata_to_binary()}

        [:box | _] ->
          :box

        [{:star, k}] ->
          k
      end)
    end
  end

  @impl true
  def frame(state, t, env) do
    fr = %{
      spin: t * 0.045,
      # Clouds run a little ahead of the ground.
      drift: t * 0.012,
      ey: @ec_y - @rise * (0.5 - 0.5 * :math.cos(t / @rise_t * :math.pi() * 2)),
      light: state.light,
      half: state.half,
      tilt: state.tilt,
      cloud: state.cloud,
      tex: state.tex,
      bounds: if(state.exact?, do: nil, else: state.bounds),
      exact?: state.exact?
    }

    {box, lut} =
      Enum.map_reduce(state.box, state.lut, fn {r, r5, cells}, lut ->
        box_row(cells, r, r5 - fr.ey, fr, lut)
      end)

    {stars, lut} =
      Enum.map_reduce(state.stars, lut, fn {k, x, r, s, p, ph, core?, still}, lut ->
        v = s * (0.86 + 0.14 * :math.sin(t / p * :math.pi() * 2 + ph))
        {cell, lut} = twinkle(x, r, v, core?, still, fr.bounds, lut)
        {{k, cell}, lut}
      end)

    stars = Map.new(stars)

    {lines, _} =
      Enum.map_reduce(state.rows, box, fn items, box ->
        {box_cells, rest} = if :box in items, do: {hd(box), tl(box)}, else: {nil, box}
        {Enum.map(items, &item(&1, box_cells, stars)), rest}
      end)

    text = lines |> Enum.map(fn line -> Enum.map(line, &elem(&1, 0)) end)
    colors = if env.color?, do: IO.iodata_to_binary(for line <- lines, {_, c} <- line, do: c)
    {Enum.intersperse(text, ?\n), colors, %{state | lut: lut}}
  end

  defp item({_text, _colors} = run, _box, _stars), do: run

  defp item(:box, box, _stars),
    do: {Enum.map(box, &elem(&1, 0)), Enum.map(box, &elem(&1, 1))}

  defp item(k, _box, stars), do: Map.fetch!(stars, k)

  defp twinkle(x, r, v, true, _still, bounds, lut),
    do: dot({x, r}, {v * 0.97, v * 0.98, v}, 0.0, 1.0, bounds, lut)

  defp twinkle(x, r, v, false, {sr, sg, sb}, bounds, lut),
    do: dot({x, r}, {max(sr, v * 0.95), max(sg, v), max(sb, v * 1.15)}, 0.0, 0.6, bounds, lut)

  defp box_row(cells, r, dy, fr, lut) do
    Enum.map_reduce(cells, lut, fn
      {:still, cell}, lut -> {cell, lut}
      cell, lut -> box_cell(cell, r, dy, fr, lut)
    end)
  end

  defp box_cell({x, dx, sr, sg, sb, scap, still}, r, dy, fr, lut)
       when is_float(dx) and is_float(dy) do
    if dx * dx + dy * dy > @reach2 and not fr.exact? do
      {still, lut}
    else
      d = JSMath.hypot(dx, dy)
      {rgb, cap, air?} = air(dx, dy, float!(d), {sr, sg, sb}, scap, fr.light)

      cond do
        d < @er ->
          {rgb, cap, fl} = globe(dx, dy, rgb, fr)
          dot({x, r}, rgb, fl, cap, fr.bounds, lut)

        air? or fr.exact? ->
          dot({x, r}, rgb, 0.0, cap, fr.bounds, lut)

        true ->
          {still, lut}
      end
    end
  end

  # The Earth's air, a thin blue rim on its sunlit side.
  defp air(dx, dy, d, {cr, cg, cb}, cap, {l0, l1, _})
       when d >= @er - 1 and d < @er + 12 and is_float(l0) and is_float(l1) and is_float(cr) and
              is_float(cg) and is_float(cb) do
    side = smooth(-0.3, 0.75, (dx * l0 - dy * l1) / d)
    g = float!(:math.exp(-max(0.0, d - @er) / 1.2)) * 0.55 * side

    # No stray haze dots out in space.
    if g < 0.05,
      do: {{cr, cg, cb}, cap, false},
      else: {{cr + 0.25 * g, cg + 0.52 * g, cb + 1.0 * g}, 1.0, true}
  end

  defp air(_dx, _dy, _d, rgb, cap, _light), do: {rgb, cap, false}

  defp globe(dx, dy, {cr, cg, cb}, %{light: {l0, l1, l2}, half: {h0, h1, h2}} = fr)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(l0) and is_float(l1) and
              is_float(l2) and is_float(h0) and is_float(h1) and is_float(h2) do
    {ct, st, cn, sn} = fr.tilt
    nx = dx / @er
    ny = -dy / @er
    q2 = nx * nx + ny * ny
    # Never the root of a negative (NaN in JS), though the disc moves with t:
    # dx is always one of the 44 half-integers inside it, and for each, every
    # double dy within 3000 ulps of the rim, above and below, gives
    # `hypot(dx, dy) >= 22` or `q2 <= 1` (checked exhaustively); farther from
    # the rim the two are 60 times their rounding error from disagreeing.
    nz = :math.sqrt(1 - q2)
    # Into the globe's own frame: tip the pole toward us, then lean it.
    {ax, ay, az} = lean(nx, ny, nz, ct, st, cn, sn)
    lat = float!(:math.asin(max(-1.0, min(1.0, ay))))
    lon = float!(:math.atan2(ax, az)) + @lon0 + float!(fr.spin)
    vy = (0.5 - lat / :math.pi()) * @th - 0.5
    ndl = nx * l0 + ny * l1 + nz * l2
    # Full sun at the right limb, dimming toward the terminator, so the disc
    # reads as a ball.
    day = smooth(-0.005, 0.06, ndl) * (0.45 + 0.8 * :math.sqrt(clamp(ndl)))
    dusk = float!(:math.exp(-sq((ndl - 0.02) / 0.035)))
    drift = float!(fr.drift)
    cl = sample(fr.cloud, lon + drift, vy)
    # The cloud's own shadow, offset away from the sun.
    sh = sample(fr.cloud, lon + drift - 0.03, vy + 0.4)
    {er, eg, eb, sw} = sample_surface(fr.tex, lon, vy)
    shade = 1 - 0.45 * sh * (1 - cl)
    er = mix(er * shade, 0.95, cl) * (day * (1 + 0.06 * dusk))
    eg = mix(eg * shade, 0.97, cl) * (day * (1 - 0.03 * dusk))
    eb = mix(eb * shade, 1.0, cl) * (day * (1 - 0.1 * dusk))
    hv = nx * h0 + ny * h1 + nz * h2
    glint = if hv > 0, do: float!(:math.pow(hv, 70)) * 0.8 * sw * (1 - cl), else: 0.0
    s = smooth(0, 0.3, ndl)
    rim = if s == 0, do: 0.0, else: float!(:math.pow(1 - nz, 2.2)) * s
    # A crisp edge where the disc meets space; the night side is a void.
    edge = smooth(1, 0.95, :math.sqrt(q2))

    {
      {mix(cr, er + (glint * 0.95 + rim * 0.2), edge),
       mix(cg, eg + (glint * 0.92 + rim * 0.42), edge),
       mix(cb, eb + (glint * 0.85 + rim * 0.85), edge)},
      # Land keeps its earth tones instead of washing out to cream.
      mix(1.0, 0.66, (1 - sw) * (1 - cl) * smooth(0.95, 0.85, abs(ay))),
      # The day side is the brightest thing in the sky: full, round dots.
      0.15 * min(1.0, day) * edge
    }
  end

  defp lean(nx, ny, nz, ct, st, cn, sn)
       when is_float(nx) and is_float(ny) and is_float(nz) and is_float(ct) and is_float(st) and
              is_float(cn) and is_float(sn) do
    ay0 = -nx * st + ny * ct
    {nx * ct + ny * st, ay0 * cn - nz * sn, ay0 * sn + nz * cn}
  end
end
