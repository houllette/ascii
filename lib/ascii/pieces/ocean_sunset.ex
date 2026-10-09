defmodule Ascii.Pieces.OceanSunset do
  @moduledoc """
  The sun sets past a pine headland, lit cloud, glitter on rolling sea.

  Golden hour at sea. The sun rests on the horizon beyond a dark pine
  headland, heaped cloud overhead lit from below, a glitter path running
  across the water toward us, and long swells rolling in, their crests
  catching the light.

  Shaded in colour per cell on a square grid, then drawn as a halftone: dot
  size is brightness, ordered-dithered, in the palette colour nearest its hue.
  The land and clear sky are built once, the clouds are wrapping fields that
  drift, and the sea is shaded each frame. A small sloop sits dark against
  the glow just left of the sun.

  Ported from `src/pieces/ocean-sunset.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Hash, Palette, Scene}
  import Bitwise

  @meta %Ascii.Meta{
    name: "ocean sunset",
    category: :scenes,
    note: "the sun sets past a pine headland, lit cloud, glitter on rolling sea",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#0b0817",
    palette: [
      "#140f2c",
      "#1e1640",
      "#2b1c52",
      "#3d2266",
      "#552a74",
      "#6e2c78",
      "#90327c",
      "#b23c7c",
      "#d24f7a",
      "#ea6a78",
      "#c2306a",
      "#ff5d8f",
      "#ff8a9a",
      "#7a2456",
      "#f05d5e",
      "#f2804f",
      "#f99a43",
      "#ffb44a",
      "#ffcd62",
      "#ffe39a",
      "#fff5d8",
      "#a8323c",
      "#d2453c",
      "#e8603e",
      "#2f1a3e",
      "#47234f",
      "#63305c",
      "#874266",
      "#ac5b70",
      "#ff9e86",
      "#ffc4a2",
      "#ffdcc0",
      "#0e1230",
      "#171a46",
      "#232059",
      "#33286a",
      "#4a2f78",
      "#1c2a5c",
      "#2e4078",
      "#7d3f8f",
      "#a24f98",
      "#c8649e",
      "#de8bb5"
    ]
  }

  @w 200
  @h 100
  # The horizon.
  @hz 56
  @sun_x 134
  @sun_y @hz - 4.5
  # The sun's radius.
  @sr 8.5
  # The sloop's mast.
  @boat 112
  # Wind chop on the swell: {dir x, dir z, wavenumber, slope, speed, offset}.
  @chop [
    {-0.45, 0.89, 22, 0.07, 2.1, 0.4},
    {0.5, 0.87, 37, 0.06, 2.9, 2.1},
    {-0.15, 0.99, 61, 0.05, 3.7, 4.4},
    {0.3, 0.95, 97, 0.04, 4.6, 1.3}
  ]
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()
  # Pines on the headland: {x, height, half width at the foot}.
  @pines [
    {2.5, 10, 2.6},
    {8, 13, 3},
    {13, 18, 3.6},
    {18.5, 11, 2.8},
    {24, 20, 3.8},
    {30, 12, 2.9},
    {35, 8, 2.3},
    {39.5, 5, 1.8}
  ]
  # The sky's gradient, top to horizon, as {stop, r, g, b}.
  @stops {
    {0, 0.08, 0.1, 0.3},
    {0.3, 0.15, 0.1, 0.34},
    {0.52, 0.4, 0.15, 0.4},
    {0.72, 0.68, 0.27, 0.4},
    {0.88, 0.8, 0.32, 0.4},
    {1, 0.88, 0.4, 0.4}
  }
  @landw 60
  @landh @hz + 10
  # The cloud deck's plane, and the low bars' width; both wrap.
  @u 640
  @cw 720
  @two_pi 2 * :math.pi()
  @sea_h @h - @hz

  @impl true
  def meta, do: @meta

  # Called for nearly every cell of every frame: local, so they inline.
  @compile {:inline,
            clamp: 1, smooth: 3, mix: 3, noise: 2, imul_x: 1, imul_y: 1, mix_hash: 1, fround: 1}
  defp clamp(v) when v < 0, do: 0
  defp clamp(v) when v > 1, do: 1
  defp clamp(v), do: v

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  defp fround(x), do: JSMath.fround(x)

  # `Ascii.Kit.Scene.noise/3` with period 0, and in it the scenes' hash
  # (`Ascii.Kit.Hash.scene/2`) of the four lattice points, written out
  # here so that the products shared between them are made once and all of
  # it inlines: `imul` in unsigned arithmetic, wrapped modulo 2^32 where JS
  # wraps.
  defp noise(x, y) do
    xi = floor(x)
    yi = floor(y)
    fx = x - xi
    fy = y - yi
    u = fx * fx * (3 - 2 * fx)
    v = fy * fy * (3 - 2 * fy)
    x0 = imul_x(xi)
    x1 = imul_x(xi + 1)
    y0 = imul_y(yi)
    y1 = imul_y(yi + 1)
    a = mix_hash(x0 + y0)
    b = mix_hash(x1 + y0)
    c = mix_hash(x0 + y1)
    d = mix_hash(x1 + y1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

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

  defp fbm(x, y, octaves, period), do: Scene.fbm(x, y, octaves, period)

  # The sky's gradient at v.
  defp gradient(v) do
    i = Enum.find(1..4, 5, fn i -> v <= elem(elem(@stops, i), 0) end)
    {a0, a1, a2, a3} = elem(@stops, i - 1)
    {b0, b1, b2, b3} = elem(@stops, i)
    k = clamp((v - a0) / (b0 - a0))
    {mix(a1, b1, k), mix(a2, b2, k), mix(a3, b3, k)}
  end

  # The headland: its skyline row at x, and the row where its foot meets the sea.
  defp ridge(x) do
    q = (x - 19) / 9

    @hz + 2.5 - 11 * :math.pow(smooth(54, 32, x), 0.7) - 2.4 * :math.exp(-(q * q)) -
      2 * fbm(x * 0.21, 3.3, 3, 0)
  end

  defp shore(x), do: @hz + 1.5 + 5 * smooth(54, 4, x)

  # A sea stack off the point.
  defp stack(x) when x > 52 and x < 58,
    do: @hz - 3.5 - 1.6 * fbm(x * 0.6, 8.1, 2, 0) + 2.5 * :math.pow((x - 55) / 3, 4)

  defp stack(_x), do: 1.0e9

  @impl true
  def init(_options) do
    land = land()
    sky = sky()
    {sky_rows, sky_builds} = Enum.unzip(for r <- 0..(@hz - 1), do: sky_row(r))

    # The cloud deck: only the rows the sky ever looks up at are built.
    deck_rows = for {{iv, _fv}, _, _, _} <- sky_rows, do: iv
    {lo_all, lo_lit} = low_bars()
    # Rows the low bars never reach are passed over.
    lo_cover =
      lo_all
      |> Tuple.to_list()
      |> Enum.map(fn row ->
        if row |> Tuple.to_list() |> Enum.all?(&(&1 == 0)), do: nil, else: row
      end)
      |> List.to_tuple()

    sky_cells =
      for {build, r} <- Enum.with_index(sky_builds) do
        List.to_tuple(for x <- 0..(@w - 1), do: sky_cell(x, r, sky, land, build))
      end

    %{
      sky_rows: List.to_tuple(sky_rows),
      sky_cells: List.to_tuple(sky_cells),
      deck: deck(Enum.min(deck_rows), Enum.max(deck_rows) + 1),
      lo_cover: lo_cover,
      lo_all: lo_all,
      lo_lit: lo_lit,
      sea_rows: List.to_tuple(for r <- @hz..(@h - 1), do: sea_row(r, land)),
      sea_cells:
        List.to_tuple(
          for r <- @hz..(@h - 1),
              do: List.to_tuple(for x <- 0..(@w - 1), do: sea_cell(x, r, land))
        ),
      lut: Palette.nearest_lut(@meta.palette),
      # Set only by the tests: every shortcut below then takes its exact
      # path (`JSMath` and no margins, no precomputed dots, no skipped
      # terms), so the two can be checked against each other.
      exact?: false
    }
  end

  # --- the clear sky, built once ---------------------------------------------

  defp sky do
    for r <- 0..(@hz - 1), x <- 0..(@w - 1), into: %{} do
      y = r + 0.5
      dx = x + 0.5 - @sun_x
      dy = (y - @sun_y) * 1.6
      d = :math.sqrt(dx * dx + dy * dy)
      # Rose and violet everywhere, burning gold only toward the sun.
      near = :math.exp(-abs(dx) / 62)
      v = y / @hz
      {g0, g1, g2} = gradient(:math.pow(v, 1.0 + 0.12 * (1 - near)))
      warm = :math.exp(-abs(dx) / 36) * smooth(0.45, 1, v) * 0.9
      g0 = mix(g0, 1.0 * mix(0.6, 1, v), warm)
      g1 = mix(g1, 0.64 * mix(0.6, 1, v), warm)
      g2 = mix(g2, 0.3, warm)
      fall = mix(1, 0.86 + 0.14 * near, smooth(0.6, 1, v))
      glow = :math.exp(-d / 40) * 0.15 + :math.exp(-d / 9) * 0.1
      # High haze in long thin bands, so no stretch of sky is one flat tone.
      haze = 0.82 + 0.36 * fbm(x * 0.03, y * 0.12, 3, 0)
      a = abs(x + 0.5 - 100) / 100
      vig = (1 - 0.08 * (a * a)) * haze * fall

      {{r, x},
       {fround(g0 * (0.85 + 0.15 * near) * vig + glow),
        fround(g1 * (0.65 + 0.35 * near) * vig + glow * 0.7),
        fround(g2 * (1.1 - 0.2 * near) * vig + glow * 0.3)}}
    end
  end

  # --- the headland and its pines, and the sloop, built once -----------------

  # Each land cell as {kind, r, g, b}: 1 rock, 2 pine, 3 the sloop.
  defp land do
    # The rock's seaward edge on each row, for the light on the cliff face.
    edges =
      List.to_tuple(
        for r <- 0..(@landh - 1) do
          y = r + 0.5

          Enum.reduce(0..(@landw - 1), -1, fn x, edge ->
            if y >= ridge(x + 0.5) and y < shore(x + 0.5), do: x, else: edge
          end)
        end
      )

    headland =
      for r <- 0..(@landh - 1),
          x <- 0..(@landw - 1),
          cell = headland_cell(x, r, elem(edges, r)),
          cell != nil,
          into: %{},
          do: {{r, x}, cell}

    Map.merge(headland, sloop())
  end

  defp headland_cell(x, r, edge) do
    y = r + 0.5
    xc = x + 0.5
    t0 = ridge(xc)
    st = stack(xc)

    rock =
      if (y >= t0 and y < shore(xc)) or (y >= st and y < @hz + 1.2),
        do: rock(x, y, xc, t0, st, edge)

    Enum.reduce(@pines, rock, &pine(&1, &2, x, r, y, xc))
  end

  defp rock(x, y, xc, t0, st, edge) do
    stack? = not (y >= t0 and y < shore(xc))
    top = if stack?, do: st, else: t0
    # Dark violet rock in rough strata.
    s = 0.6 + 0.8 * fbm(x * 0.22, y * 0.7, 3, 0)
    {cr, cg, cb} = {0.06 * s, 0.042 * s, 0.15 * s}
    # The sun is low and to the right: slopes that drop toward it catch it.
    facing =
      clamp(0.4 + if(stack?, do: 0.5, else: (ridge(xc + 1.2) - ridge(xc - 1.2)) * 0.45))

    rim = smooth(top + 2.4, top + 0.4, y) * facing
    # The cliff face, warm where it turns to the sun, broken by crags.
    crag = smooth(0.35, 0.75, fbm(x * 0.4 + 3, y * 0.5, 3, 0))

    face =
      cond do
        stack? -> smooth(53.5, 57.5, xc) * 0.7
        edge > 30 -> :math.exp(-(edge - x) / 4) * smooth(@hz + 5, @hz - 4, y)
        true -> 0
      end

    lit = clamp(max(rim * 0.9, face * (0.3 + 0.7 * crag) * 0.75))
    {1, mix(cr, 0.95, lit), mix(cg, 0.38, lit * 0.95), mix(cb, 0.3, lit * 0.9)}
  end

  # A conifer: a spire that widens in tiers of branches.
  defp pine({tx, th, tw}, acc, x, r, y, xc) do
    tb = ridge(tx)
    dy = y - (tb - th)
    tier = (dy + th * 0.3) / 2.4
    half = dy / th * tw * (0.5 + 0.75 * (tier - floor(tier))) + 0.35
    ex = xc - tx

    if dy >= 0 and y < tb + 1.5 and abs(ex) <= half do
      s = 0.7 + 0.6 * Hash.scene(x * 13 + r, 5)
      {cr, cg, cb} = {0.045 * s, 0.03 * s, 0.1 * s}
      # The right flank faces the sun.
      e = if ex > 0 and ex > half - 1.1, do: 0.3 + 0.3 * smooth(th, 0, dy), else: 0
      {2, mix(cr, 0.85, e), mix(cg, 0.3, e), mix(cb, 0.3, e)}
    else
      acc
    end
  end

  # A small sloop out on the water, dark against the glow left of the sun.
  defp sloop do
    for r <- (@hz - 10)..(@hz + 3),
        x <- (@boat - 6)..(@boat + 6),
        cell = sloop_cell(x, r),
        cell != nil,
        into: %{},
        do: {{r, x}, cell}
  end

  defp sloop_cell(x, r) do
    y = r + 0.5
    ex = x + 0.5 - @boat
    hull = y >= @hz + 1 and y < @hz + 3 and abs(ex - 0.3) < 4.6 - (y - @hz - 1) * 1.3
    mast = abs(ex) < 0.5 and y >= @hz - 9 and y < @hz + 1
    main = ex > 0 and y >= @hz - 8.5 and y < @hz + 0.5 and ex < 0.6 + (y - (@hz - 8.5)) * 0.42
    jib = ex < 0 and y >= @hz - 7 and y < @hz + 0.5 and -ex < (y - (@hz - 7)) * 0.36

    if hull or mast or main or jib do
      # The sails are thin enough to glow a little with the sun behind them.
      glow = if main, do: 0.12 + 0.18 * smooth(0, 3.5, ex), else: 0
      {3, 0.05 + glow, 0.03 + glow * 0.45, 0.09 + glow * 0.35}
    end
  end

  defp land_at(land, r, x) do
    case land do
      %{{^r, ^x} => {kind, cr, cg, cb}} -> {kind, fround(cr), fround(cg), fround(cb)}
      _ -> nil
    end
  end

  # --- the clouds ---------------------------------------------------------

  defp deck_at(u, v) do
    q = fbm(u * 0.0125, v * 0.06, 2, 8)
    patch = fbm(u * 0.00625, v * 0.03 + 7, 2, 4)
    fbm(u * 0.040625 + q * 1.6, v * 0.3, 5, 26) + 0.25 * (patch - 0.5)
  end

  # Rows `from..to` of the deck, as {cover, lit} tuples by row (nil elsewhere).
  defp deck(from, to) do
    rows =
      for v <- from..to do
        row =
          for u <- 0..(@u - 1) do
            d = deck_at(u, v)
            # The side of each heap that faces the horizon, and the sun, is lit.
            {fround(d), fround(clamp(0.5 + (d - deck_at(u, v + 2.5)) * 9))}
          end

        {v,
         {row |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
          row |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}}
      end
      |> Map.new()

    List.to_tuple(for v <- 0..to, do: Map.get(rows, v))
  end

  defp lower(x, y) do
    # Long thin bars low over the horizon.
    b = fbm(x / 40, y * 0.3, 4, @cw / 40)
    gaps = fbm(x / 120, 5, 2, @cw / 120)

    b + 0.01 + 0.5 * (gaps - 0.5) - 0.35 * smooth(@hz - 14, @hz - 20, y) -
      0.25 * smooth(@hz - 4, @hz - 1, y)
  end

  defp low_bars do
    rows =
      for r <- 0..(@hz - 1) do
        y = r + 0.5

        row =
          for x <- 0..(@cw - 1) do
            dl = lower(x, y)
            {fround(smooth(0.58, 0.66, dl)), fround(clamp(0.5 + (dl - lower(x, y + 1.2)) * 6))}
          end

        {row |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
         row |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
      end

    {rows |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
     rows |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
  end

  # --- what each sky row and cell keeps ------------------------------------

  # Per sky row, for the frame: where it looks up at the deck, the cloud's
  # weight there, how low it sits, the deck's shadow colour; and for building
  # its cells: the deck's distance, the cloud band and the stars' fade.
  defp sky_row(r) do
    y = r + 0.5
    v = y / @hz
    # The cloud deck, found on its plane: far rows are far away.
    d = 58 / (@hz - y + 2.5)
    # A band of heaped cloud mid-sky: clear above and clear in the low glow.
    far = smooth(4.8, 2.7, d) * smooth(1.08, 1.7, d)
    sv = (d - 0.9) * 10
    iv = floor(sv)

    {{if(far > 0, do: {iv, sv - iv}), :math.sqrt(far), v * v,
      {mix(0.1, 0.2, v), mix(0.065, 0.07, v), mix(0.23, 0.27, v)}},
     {d, far, v * v, if(r < 22, do: smooth(22, 4, r))}}
  end

  defp sky_cell(x, r, sky, land, {d, far, low, star_sm}) do
    y = r + 0.5
    {cr, cg, cb} = Map.fetch!(sky, {r, x})
    dx = x + 0.5 - @sun_x
    dy = y - @sun_y
    q = dy / 0.9
    ds = :math.sqrt(dx * dx + q * q)

    {cr, cg, cb, disc} =
      if ds < @sr + 0.6 do
        # The disc, a little flattened, hot at the core and redder at the rim.
        e = ds / @sr
        disc = smooth(@sr + 0.45, @sr - 0.45, ds)
        e4 = e * e * e * e

        {mix(cr, 1.0, disc), mix(cg, 0.95 - 0.2 * e4, disc), mix(cb, 0.78 - 0.38 * e4, disc),
         disc}
      else
        {cr, cg, cb, 0}
      end

    near = :math.exp(-:math.sqrt(dx * dx + dy * dy * 2.5) / 45)

    cloud =
      if far > 0 do
        az = :math.exp(-abs(dx) / 60)
        warm = clamp(az * (0.1 + 1.2 * low))
        thin_top = fround(fbm(x * 0.05 + 11, r * 0.15, 2, 0))

        {dx * d, 0.22 * (1 - far) * thin_top, az, 0.55 + 0.25 * low + 0.35 * az,
         mix(0.45, 0.72, warm), mix(0.52, 0.38, warm)}
      end

    # Low bars: thinned over the sun and kept off the sky behind the headland.
    q13 = dx / 13
    bars = {1 - 0.75 * :math.exp(-(q13 * q13)), 1 - 0.85 * smooth(76, 50, x), 0.35 + 0.9 * near}

    star =
      if star_sm != nil and Hash.scene(x, r * 5 + 3) > 0.993,
        do: {0.8 + Hash.scene(r, x) * 1.6, Hash.scene(x, r) * 6.28, star_sm}

    keep = 1 - 0.75 * disc
    sk = {fround(cr * keep), fround(cg * keep), fround(cb * keep)}

    ht =
      case land_at(land, r, x) do
        {_kind, lr, lg, lb} -> {:land, static_halftone(x, r, lr, lg, lb, 0.02, 1), {lr, lg, lb}}
        nil -> {:sky, static_halftone(x, r, cr, cg, cb, 0.05, 1)}
      end

    {cr, cg, cb, keep, sk, cloud, bars, star, ht}
  end

  # --- what each sea row and cell keeps ------------------------------------

  defp sea_row(r, land) do
    y = r + 0.5
    # The sea: each cell is a facet of water that mirrors whatever part of the
    # sky its tilt points it at.
    dz = y - @hz
    # How much sea one row spans.
    rows = 36 / (dz * dz)
    swell = smooth(8, 26, dz)
    hot = :math.exp(-dz / 9)
    fy = 1.6 / (1 + dz * 0.05)
    fres = 0.24 + 0.46 * :math.exp(-dz / 8)
    depth = smooth(@hz, @h, y)

    chop = List.to_tuple(for {_, _, kk, _, _, _} <- @chop, do: clamp(1.6 / (kk * rows)))

    headland = if dz < 26, do: headland_row(y, land)
    sloop = if dz > 2.5 and dz < 14, do: sloop_row(y, land)

    {y, dz, @hz - 1 - dz * 0.85, clamp(1.4 / (13 * rows)), chop,
     {y * fy * 1.1, y * fy * 1.3, y * fy * 2, y * 0.9}, {fres, 0.01 * depth, 0.03 * depth},
     {swell, 0.7 * swell, 0.55 + 0.3 * hot, 0.2 + 0.25 * hot}, smooth(0, 3, dz),
     smooth(@h + 6, @h - 4, y), headland, sloop}
  end

  # The headland upside down in the water: for each column it may be read
  # from, its foot, what it mirrors there, and the surf line.
  defp headland_row(y, land) do
    List.to_tuple(
      for ix <- 0..(@landw - 1) do
        ft = shore(ix + 0.5)

        if y > ft do
          my = floor(2 * ft - y)

          mirror =
            with true <- my >= 0 and my < @landh,
                 {_kind, lr, lg, lb} <- land_at(land, my, ix) do
              {0.8 * smooth(ft + 24, ft + 4, y), lr * 0.8 + 0.02, lg * 0.7 + 0.015,
               lb * 0.85 + 0.05}
            else
              _ -> nil
            end

          {mirror, smooth(ft + 1.6, ft + 0.3, y)}
        end
      end
    )
  end

  # And the sloop's: which columns of its mirrored row are the boat.
  defp sloop_row(y, land) do
    m = floor(2 * (@hz + 3) - y)

    boat =
      for x <- 0..(@w - 1), match?({3, _, _, _}, land_at(land, m, x)), into: MapSet.new(), do: x

    {y * 1.3, boat, 0.7 * smooth(@hz + 14, @hz + 4, y)}
  end

  defp sea_cell(x, r, land) do
    case land_at(land, r, x) do
      {_kind, lr, lg, lb} -> {:land, static_halftone(x, r, lr, lg, lb, 0.02, 1), {lr, lg, lb}}
      nil -> water_cell(x, r)
    end
  end

  defp water_cell(x, r) do
    y = r + 0.5
    dz = y - @hz
    # Distance out.
    z = 36 / dz
    hot = :math.exp(-dz / 9)
    # The glitter path, wider as it comes toward us.
    pw = 3 + dz * 0.8
    fx = 0.9 / (1 + dz * 0.06) * 0.35
    dx = x + 0.5 - @sun_x
    xx = (x + 0.5 - 100) / dz
    # The long swell rolls toward us; shorter chop rides on it.
    p0 = 13 * (z + 0.05 * xx) + 2.2 * fbm(xx * 0.35 + 3, z * 0.4, 2, 0)
    chop = List.to_tuple(for {kx, kz, kk, _, _, _} <- @chop, do: kk * (kx * xx + kz * z))
    qp = dx / pw
    path = :math.exp(-(qp * qp))
    qs = dx / (pw * 1.6)
    soft = :math.exp(-(qs * qs))
    th = 0.84 - 0.3 * path * (0.45 + 0.55 * hot)
    qc = dx / (1.0 + dz * 0.22)

    {:water, p0, chop, {x * fx * 1.4 + 13, x * fx, x * fx * 1.7, xx * 2.5 + 7, x * 0.18},
     {th, th + 0.08, th + 0.04, th + 0.2, 0.25 + 0.75 * path, path * path, soft},
     {0.2 * soft * (0.4 + hot), 0.1 * soft * (0.4 + hot), 0.04 * soft},
     {0.15 + 0.85 * soft, mix(0.3, 0.7, soft), mix(0.5, 0.3, soft)},
     :math.exp(-(qc * qc)) * :math.exp(-dz / 5)}
  end

  # --- the halftone ---------------------------------------------------------

  # Dot and colour for a cell that never changes: its character, and its
  # colour as the palette lookup takes it (the cache key, then the colour).
  defp static_halftone(x, r, cr, cg, cb, floor, fade) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(floor + (1 - floor) * :math.pow(peak, 0.85) * 0.95) * fade
    step = max(0, min(3, JSMath.round(level * 3 + elem(@bayer, band(r, 3) * 4 + band(x, 3)))))
    {tr, tg, tb} = tint(step, level, peak, cr, cg, cb)
    {elem(@dots, step), key(tr, tg, tb), tr, tg, tb}
  end

  # Small dots are drawn brighter to make up their size, but the darkest
  # cells keep a dim colour, so the shadows stay deep instead of glittering.
  defp tint(step, level, peak, cr, cg, cb) do
    want = if step != 0, do: min(1, (level + 0.06) / elem(@cover, step)), else: 0
    s = (0.3 + 0.7 * want) * (0.4 + 0.6 * smooth(0.14, 0.5, level)) / peak
    {clamp(cr * s), clamp(cg * s), clamp(cb * s)}
  end

  # The nearest-colour cache's key, as `Ascii.Kit.Palette.nearest/4` makes it.
  defp key(r, g, b),
    do: bsl(cube(r), 10) ||| bsl(cube(g), 5) ||| cube(b)

  defp cube(v), do: min(31, trunc(v * 31.99))

  defp lookup({_palette, answers} = lut, key, tr, tg, tb) do
    case answers do
      %{^key => i} -> {i, lut}
      _ -> Palette.nearest(lut, tr, tg, tb)
    end
  end

  # Dot size from brightness, dithered, and the colour making up what the
  # dot size could not.
  defp halftone(x, r, cr, cg, cb, floor, fade, color?, lut) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(floor + (1 - floor) * :math.pow(peak, 0.85) * 0.95) * fade
    step = max(0, min(3, JSMath.round(level * 3 + elem(@bayer, band(r, 3) * 4 + band(x, 3)))))

    if color? do
      {tr, tg, tb} = tint(step, level, peak, cr, cg, cb)
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

  # --- the frame ------------------------------------------------------------

  @impl true
  def frame(state, t, env) do
    color? = env.color?
    fr = {t, t * 0.9, t * 1.7, state.exact?}
    {sky, sk, lut} = sky_lines(0, state, fr, color?, state.lut, [], [])

    {sea, lut} =
      sea_lines(0, state, sea_frame(t, state.exact?), List.to_tuple(sk), color?, lut, [])

    lines = sky ++ sea
    text = lines |> Enum.map(&elem(&1, 0)) |> Enum.intersperse(?\n)
    colors = if color?, do: IO.iodata_to_binary(Enum.map(lines, &elem(&1, 1)))
    {text, colors, %{state | lut: lut}}
  end

  # --- the sky in a frame --------------------------------------------------

  defp sky_lines(@hz, _state, _fr, _color?, lut, lines, sk),
    do: {:lists.reverse(lines), :lists.reverse(sk), lut}

  defp sky_lines(r, state, fr, color?, lut, lines, sk) do
    {deck, sqrt_far, low, shadow} = elem(state.sky_rows, r)

    deck =
      case deck do
        {iv, fv} ->
          {c0, l0} = elem(state.deck, iv)
          {c1, l1} = elem(state.deck, iv + 1)
          {c0, c1, l0, l1, fv}

        nil ->
          nil
      end

    lc = elem(if(elem(fr, 3), do: state.lo_all, else: state.lo_cover), r)
    ctx = {r, deck, lc, elem(state.lo_lit, r), sqrt_far, low, shadow, fr, color?}

    {chars, colors, row_sk, lut} =
      sky_cells(0, elem(state.sky_cells, r), ctx, lut, <<>>, <<>>, [])

    sky_lines(r + 1, state, fr, color?, lut, [{chars, colors} | lines], [row_sk | sk])
  end

  defp sky_cells(@w, _cells, _ctx, lut, chars, colors, sk),
    do: {chars, colors, sk |> :lists.reverse() |> List.to_tuple(), lut}

  defp sky_cells(x, cells, ctx, lut, chars, colors, sk) do
    {ch, i, cell_sk, lut} = sky_px(x, elem(cells, x), ctx, lut)

    sky_cells(x + 1, cells, ctx, lut, <<chars::binary, ch::binary>>, <<colors::binary, i>>, [
      cell_sk | sk
    ])
  end

  defp sky_px(x, cell, ctx, lut) do
    {cr, cg, cb, keep, sk, cloud, bars, star, ht} = cell
    {r, deck, lc, ll, sqrt_far, low, shadow, {t, d_up, d_lo, exact?}, color?} = ctx
    {cr, cg, cb, cover} = deck(deck, cloud, d_up, sqrt_far, low, shadow, cr, cg, cb)
    {cr, cg, cb, cover} = bars(x, lc, ll, d_lo, bars, cover, cr, cg, cb)
    {cr, cg, cb, moved} = star(star, t, cover, cr, cg, cb)
    moved = moved or cover > 0 or exact?
    # The sea is too rough to mirror the disc whole: it gives back glitter.
    sk = if moved, do: {fround(cr * keep), fround(cg * keep), fround(cb * keep)}, else: sk

    {ch, i, lut} =
      case ht do
        {:land, _static, {lr, lg, lb}} when exact? ->
          halftone(x, r, lr, lg, lb, 0.02, 1, color?, lut)

        {:land, static, _land} ->
          paint(static, color?, lut)

        {:sky, static} when not moved ->
          paint(static, color?, lut)

        {:sky, _} ->
          sky_dot(x, r, cr, cg, cb, {color?, exact?}, lut)
      end

    {ch, i, sk, lut}
  end

  defp sky_dot(x, r, cr, cg, cb, {color?, _exact?}, lut),
    do: halftone(x, r, cr, cg, cb, 0.05, 1, color?, lut)

  # The cloud deck, found on its plane.
  defp deck(
         {c0, c1, l0, l1, fv},
         {dxd, thin, az, bmul, hg, hb},
         d_up,
         sqrt_far,
         low,
         shadow,
         cr,
         cg,
         cb
       ) do
    su = dxd + d_up + 64_200
    iu = floor(su)
    fu = su - iu
    iu = rem(iu, @u)
    iu1 = rem(iu + 1, @u)
    a = elem(c0, iu)
    d0 = a + (elem(c0, iu1) - a) * fu
    a = elem(c1, iu)
    d1 = a + (elem(c1, iu1) - a) * fu
    dd = d0 + (d1 - d0) * fv - thin
    c = smooth(0.56, 0.68, dd) * sqrt_far

    if c > 0.01 do
      a = elem(l0, iu)
      la = a + (elem(l0, iu1) - a) * fu
      a = elem(l1, iu)
      lb = a + (elem(l1, iu1) - a) * fu
      l = la + (lb - la) * fv
      # Undersides glow gold toward the sun and rose away from it, and more
      # the lower they sit; thick cores stay dusk violet.
      th = 1 - smooth(0.6, 0.76, dd)
      b = clamp(:math.pow(smooth(0.45, 0.85, l), 1.5) * bmul + 0.3 * th * az * low)
      {sr, sg, sb} = shadow
      {mix(cr, mix(sr, 1.0, b), c), mix(cg, mix(sg, hg, b), c), mix(cb, mix(sb, hb, b), c), c}
    else
      {cr, cg, cb, 0}
    end
  end

  defp deck(_deck, _cloud, _d_up, _sqrt_far, _low, _shadow, cr, cg, cb), do: {cr, cg, cb, 0}

  # The low bars, dark against the glow with burning edges.
  defp bars(_x, nil, _ll, _d_lo, _bars, cover, cr, cg, cb), do: {cr, cg, cb, cover}

  defp bars(x, lc, ll, d_lo, {f1, f2, rimk}, cover, cr, cg, cb) do
    sx = x + d_lo
    ix = floor(sx)
    fx = sx - ix
    i0 = rem(ix, @cw)
    i1 = rem(ix + 1, @cw)
    a = elem(lc, i0)
    c = (a + (elem(lc, i1) - a) * fx) * f1 * f2

    if c > 0.01 do
      a = elem(ll, i0)
      l = a + (elem(ll, i1) - a) * fx
      rim = l * l * rimk
      a = min(1, c * 1.2) * 0.92

      {mix(cr, 0.3 + 0.7 * rim, a), mix(cg, 0.09 + 0.55 * rim, a), mix(cb, 0.24 + 0.18 * rim, a),
       max(cover, c)}
    else
      {cr, cg, cb, cover}
    end
  end

  # The first stars, high up where the sky has gone to indigo.
  defp star({speed, phase, sm}, t, cover, cr, cg, cb) when cover < 0.05 do
    tw = 0.55 + 0.45 * :math.sin(t * speed + phase)
    st = tw * sm * 0.75
    {max(cr, st * 0.95), max(cg, st * 0.85), max(cb, st), true}
  end

  defp star(_star, _t, _cover, cr, cg, cb), do: {cr, cg, cb, false}

  # --- the sea in a frame --------------------------------------------------

  defp sea_frame(t, exact?) do
    {exact?, t * 0.8, {2.1 * t, 2.9 * t, 3.7 * t, 4.6 * t}, t * 0.15, t * 0.25, t * 0.3, t * 0.4,
     t * 0.5, t * 1.2, t * 1.6,
     List.to_tuple(for x <- 0..(@landw + 3), do: noise(x * 0.5 - t * 0.4, t * 0.3))}
  end

  defp sea_lines(@sea_h, _state, _fr, _sk, _color?, lut, lines), do: {:lists.reverse(lines), lut}

  defp sea_lines(i, state, fr, sk, color?, lut, lines) do
    row = elem(state.sea_rows, i)

    row =
      case elem(row, 11) do
        {y13, boat, ak} -> put_elem(row, 11, {0.9 * :math.sin(y13 + elem(fr, 9)), boat, ak})
        nil -> row
      end

    {chars, colors, lut} =
      sea_cells(0, elem(state.sea_cells, i), {@hz + i, row, fr, sk, color?}, lut, <<>>, <<>>)

    sea_lines(i + 1, state, fr, sk, color?, lut, [{chars, colors} | lines])
  end

  defp sea_cells(@w, _cells, _ctx, lut, chars, colors), do: {chars, colors, lut}

  defp sea_cells(x, cells, {r, _row, fr, _sk, color?} = ctx, lut, chars, colors) do
    {ch, i, lut} =
      case elem(cells, x) do
        {:land, static, {lr, lg, lb}} ->
          if elem(fr, 0),
            do: halftone(x, r, lr, lg, lb, 0.02, 1, color?, lut),
            else: paint(static, color?, lut)

        water ->
          water_px(x, water, ctx, lut)
      end

    sea_cells(x + 1, cells, ctx, lut, <<chars::binary, ch::binary>>, <<colors::binary, i>>)
  end

  # A cell of water.
  defp water_px(x, water, {r, row, _fr, _sk, color?} = ctx, lut) do
    {cr, cg, cb} = water(x, water, ctx)
    halftone(x, r, cr, cg, cb, 0.18, elem(row, 9), color?, lut)
  end

  defp water(x, water, {_r, row, fr, sk, _color?}) do
    {:water, p0, chops, {rip_x, n_x1, n_x2, crest_x, dash_x}, glints, adds, catches, col0} = water

    {y, dz, ry0, c14, chop_k, {rip_y, n_y1, n_y2, dash_y}, {fres, dep1, dep3}, swells, sm3, _fade,
     headland, sloop} = row

    {forced?, t08, wts, t015, t025, t03, t04, t05, t12, _t16, foam} = fr
    p = p0 + t08
    wv = :math.sin(p)
    slope = :math.cos(p)
    {ry, rx} = facet(x, chops, chop_k, wts, {slope, c14, ry0})
    # Violet near the horizon, deepening to indigo toward us, broken into
    # long horizontal ripples, each giving back a little more or less of the
    # sky.
    rip = noise(rip_x - t015, rip_y + t025)
    rf = fres * (0.5 + 1.1 * rip * rip)
    {skr, skg, skb} = sk |> elem(ry) |> elem(rx)
    cr = skr * rf * 0.8 + 0.03 - dep1
    cg = skg * rf * 0.75 + 0.022
    cb = skb * rf + 0.095 + dep3
    # Ripple facets that catch the sun: short dashes far out, longer close
    # in, each turning toward the sun and away again.
    n = 0.55 * noise(n_x1 + t03, n_y1 - t04) + 0.45 * noise(n_x2 - t04, n_y2 + t03 + 40)
    {cr, cg, cb} = glitter(swells, glints, adds, slope, n, cr, cg, cb)
    {cr, cg, cb} = crest(swells, catches, crest_x, p, {wv, n, forced?}, cr, cg, cb)

    # The sun's own column: a gap under the disc, then broken dashes.
    {cr, cg, cb} =
      if col0 == 0 and not forced? do
        {cr, cg, cb}
      else
        dash = smooth(0.4, 0.7, noise(dash_x + t025, dash_y - t05))
        col = col0 * (0.6 + 0.4 * n) * sm3 * dash
        {cr + col, cg + col * 0.8, cb + col * 0.45}
      end

    {cr, cg, cb} = headland(headland, x, y, t12, foam, cr, cg, cb)
    {cr, cg, cb} = sloop(sloop, x, rip, cr, cg, cb)
    # A crisp dark line at the horizon for the sun to sit on.
    if dz < 1.5, do: {cr * 0.55, cg * 0.55, cb * 0.55}, else: {cr, cg, cb}
  end

  # The row and column of sky a facet mirrors.
  defp facet(x, chops, chop_k, wts, {slope, c14, ry0}) do
    {sz, sxl} = chop(chops, chop_k, wts, 0.11 * slope * c14, 0.015 * slope)
    ry = JSMath.round(ry0 - 70 * sz)
    rx = JSMath.round(x - 60 * sxl)
    {ry |> max(0) |> min(@hz - 1), rx |> max(0) |> min(@w - 1)}
  end

  # Wind chop on the swell, tilting each facet.
  defp chop({b1, b2, b3, b4}, {k1, k2, k3, k4}, {w1, w2, w3, w4}, sz, sxl) do
    c = :math.cos(b1 - w1 + 0.4) * 0.07 * k1
    sz = sz + c * 0.89
    sxl = sxl + c * -0.45
    c = :math.cos(b2 - w2 + 2.1) * 0.06 * k2
    sz = sz + c * 0.87
    sxl = sxl + c * 0.5
    c = :math.cos(b3 - w3 + 4.4) * 0.05 * k3
    sz = sz + c * 0.99
    sxl = sxl + c * -0.15
    c = :math.cos(b4 - w4 + 1.3) * 0.04 * k4
    {sz + c * 0.95, sxl + c * 0.3}
  end

  defp glitter(
         {_swell, swell07, hot_g, hot_b},
         glints,
         {add_r, add_g, add_b},
         slope,
         n,
         cr,
         cg,
         cb
       ) do
    # The near face of a swell is in shadow.
    {cr, cg, cb} =
      if slope > 0 do
        d = 1 - swell07 * slope
        {cr * d, cg * d, cb * d}
      else
        {cr, cg, cb}
      end

    {th, th08, th04, th2, glint_k, pp, soft} = glints
    glint = smooth(th, th08, n) * glint_k * soft
    white = pp * smooth(th04, th2, n)

    {cr + (add_r + glint * 1.1), cg + (add_g + glint * (hot_g + 0.35 * white)),
     cb + (add_b + glint * (hot_b + 0.45 * white))}
  end

  # The crests catch it: gold in the path, rose out to the sides.
  # (Where the swell or the noise leaves no crest, its x ** 7 is skipped.)
  defp crest({swell, _, _, _}, _catches, _crest_x, _p, {_, _, false}, cr, cg, cb)
       when swell == 0,
       do: {cr, cg, cb}

  defp crest({swell, _, _, _}, catches, crest_x, p, {wv, n, forced?}, cr, cg, cb) do
    {catch_k, mix_g, mix_b} = catches
    wave = floor(p / @two_pi)
    k = smooth(0.4, 0.65, noise(crest_x, wave * 3.7))

    if k == 0 and not forced? do
      {cr, cg, cb}
    else
      crest = :math.pow(0.5 + 0.5 * wv, 7) * swell * k
      catch_l = crest * catch_k * (0.6 + 0.6 * n)
      {cr + catch_l * 0.95, cg + catch_l * mix_g, cb + catch_l * mix_b}
    end
  end

  # The headland upside down in the water, broken by ripples.
  defp headland(table, x, y, t12, foam, cr, cg, cb)
       when table != nil and x < @landw + 4 do
    a = y * 1.1 + t12 + x * 0.05
    ix = trunc(x + 0.5 + 1.3 * :math.sin(a)) |> min(@landw - 1) |> max(0)

    case elem(table, ix) do
      nil ->
        {cr, cg, cb}

      {mirror, surf} ->
        {cr, cg, cb} =
          case mirror do
            {a, mr, mg, mb} -> {mix(cr, mr, a), mix(cg, mg, a), mix(cb, mb, a)}
            nil -> {cr, cg, cb}
          end

        # A line of surf where rock meets water.
        foam = surf * smooth(0.45, 0.8, elem(foam, x))
        {cr + 0.5 * foam, cg + 0.3 * foam, cb + 0.35 * foam}
    end
  end

  defp headland(_table, _x, _y, _t12, _foam, cr, cg, cb), do: {cr, cg, cb}

  # And the sloop's, shorter and more broken.
  defp sloop({s09, boat, ak}, x, rip, cr, cg, cb) when x > @boat - 8 and x < @boat + 8 do
    ix = trunc(x + 0.5 + s09)

    if MapSet.member?(boat, ix) do
      a = ak * (0.6 + 0.4 * rip)
      {mix(cr, 0.04, a), mix(cg, 0.03, a), mix(cb, 0.1, a)}
    else
      {cr, cg, cb}
    end
  end

  defp sloop(_sloop, _x, _rip, cr, cg, cb), do: {cr, cg, cb}
end
