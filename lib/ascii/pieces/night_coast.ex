defmodule Ascii.Pieces.NightCoast do
  @moduledoc """
  A lighthouse turning its beam under moonlit clouds over a dark sea.

  A lighthouse on a wooded headland under moonlit clouds. The beam turns
  every eight seconds, the clouds drift, and the sea carries the moon's road
  and the lamp's reflection.

  Each frame is shaded in colour cell by cell on a square grid, then drawn as
  a halftone: every cell is a dot whose size is its brightness, ordered-
  dithered so gradients read as texture, in the palette colour nearest its
  hue.

  Ported from `src/pieces/night-coast.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.{Hash, Palette, Scene}
  import Bitwise

  @meta %Ascii.Meta{
    name: "night coast",
    category: :scenes,
    note: "a lighthouse turning its beam under moonlit clouds over a dark sea",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#080b12",
    palette: [
      "#15203d",
      "#1b2a50",
      "#223463",
      "#2b4077",
      "#364e8b",
      "#445f9f",
      "#5874b2",
      "#7089c0",
      "#8a9cc4",
      "#a3b1cf",
      "#bec9dc",
      "#d8dfea",
      "#eef1f6",
      "#f7f8fc",
      "#ffe9ae",
      "#ffd27c",
      "#f3a64a",
      "#c46c2d",
      "#121c1b",
      "#182724",
      "#203530",
      "#2c473d",
      "#3c5c4c",
      "#232a36",
      "#363e4c",
      "#555d6c",
      "#2a3550",
      "#3a4868",
      "#9c4136",
      "#ff5d4d"
    ]
  }

  @w 200
  @h 100
  @horizon 60
  @moon_x 150
  @moon_y 19
  @lamp_x 30
  @dots {" ", "·", "•", "●"}
  # How much each dot fills, against the largest.
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()
  # The clouds' width, which wraps.
  @cw 640

  @air 0
  @land 1
  @tree 2
  @tower 3
  @lantern 4
  @cap 5
  @wall 6
  @pane 7
  @roof 8
  @isle 9

  @impl true
  def meta, do: @meta

  # The dot's power is bounded from a table below POW_TOP, GRAIN steps a unit.
  @grain 1024
  @pow_top 4

  # Called for nearly every cell of every frame: local, so they inline.
  @compile {:inline,
            clamp: 1,
            smooth: 3,
            mix: 3,
            js_round: 1,
            float!: 1,
            lerp: 3,
            bilerp: 6,
            noise: 2,
            level: 3,
            step: 2,
            want: 2,
            key: 2,
            cube: 1,
            cached: 2}

  # Floats out (the same values as JS's 0 and 1), so the shading stays in
  # float arithmetic, which the BEAM runs unboxed where it can tell.
  defp clamp(v) when v < 0, do: 0.0
  defp clamp(v) when v > 1, do: 1.0
  defp clamp(v), do: v

  # A float, as far as the compiler can tell, for what a call returns.
  defp float!(v) when is_float(v), do: v

  # `Math.round`, as `Ascii.JSMath.round/1` does it for a float.
  defp js_round(x) do
    c = ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end

  defp smooth(a, b, v) do
    k = clamp((v - a) / (b - a))
    k * k * (3 - 2 * k)
  end

  defp mix(a, b, k), do: a + (b - a) * k

  defdelegate noise(x, y, period), to: Scene
  defdelegate fbm(x, y, octaves, period), to: Scene

  @impl true
  def init(_options) do
    # --- the land, built once --------------------------------------------
    top = fn x ->
      @horizon - 15 * smooth(86, 50, x) * (1 - 0.12 * smooth(24, 0, x)) -
        1.6 * fbm(x * 0.15, 3.7, 3, 0)
    end

    tops = List.to_tuple(for x <- 0..(@w - 1), do: top.(x))
    base = top.(@lamp_x)
    tower_top = base - 15
    trees = trees(top)
    cottage = top.(41)

    isles =
      List.to_tuple(
        for x <- 0..(@w - 1) do
          @horizon - 4.5 * max(0, 1 - :math.pow((x - 180) / 26, 2)) - 1.4 * fbm(x * 0.2, 9, 2, 0)
        end
      )

    land =
      for r <- 0..(@h - 1) do
        List.to_tuple(
          for x <- 0..(@w - 1) do
            land_cell(x, r, elem(tops, x), elem(isles, x), trees, base, tower_top, cottage)
          end
        )
      end
      |> List.to_tuple()

    # A faint unevenness in the clear sky, so it is never one flat tone.
    haze =
      List.to_tuple(
        for r <- 0..(@h - 1) do
          List.to_tuple(for x <- 0..(@w - 1), do: JSMath.fround(fbm(x * 0.05, r * 0.08, 3, 0)))
        end
      )

    # --- the clouds: heaps of noise that wrap, so they can drift forever --
    {cover, lit} =
      for r <- 0..(@horizon - 1) do
        y = r + 0.5

        row =
          for x <- 0..(@cw - 1) do
            d = density(x, y)
            # Lit on the side facing the moon (up and right), shadowed
            # underneath, a little darker deep inside.
            toward = density(x + 2.5, y - 3)

            {JSMath.fround(smooth(0.52, 0.63, d)),
             JSMath.fround(clamp(0.5 + (d - toward) * 11 - (d - 0.6) * 1.2))}
          end

        {row |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
         row |> Enum.map(&elem(&1, 1)) |> List.to_tuple()}
      end
      |> Enum.unzip()

    cover = List.to_tuple(cover)
    lit = List.to_tuple(lit)

    cells =
      List.to_tuple(
        for r <- 0..(@h - 1) do
          land_row = elem(land, r)
          haze_row = elem(haze, r)

          List.to_tuple(
            for x <- 0..(@w - 1),
                do: static(x, r, elem(land_row, x), elem(haze_row, x), tower_top)
          )
        end
      )

    %{
      rows: cells |> Tuple.to_list() |> Enum.map(&Tuple.to_list/1) |> Enum.with_index(),
      memo: fresh_memo(),
      cover: cover,
      lit: lit,
      tower_top: tower_top,
      bounds: pow_bounds(),
      lut: Palette.nearest_lut(@meta.palette),
      # Tests turn the fast paths off (the memo, the power's bounds, the cached
      # colours, the glow without a flash) to check that frames come out the
      # same without them.
      exact?: false
    }
  end

  defp fresh_memo, do: List.duplicate(List.duplicate(:none, @w), @h)

  defp trees(top) do
    Stream.unfold(1, fn x -> if x < 76, do: {x, x + 2.6 + Hash.scene(x * 7, 1) * 2.6} end)
    # The clearing for the tower and the cottage.
    |> Enum.reject(&(&1 > 22 and &1 < 49))
    |> Enum.map(fn x ->
      tx = x + Hash.scene(x, 2) * 1.2
      {tx, (4 + Hash.scene(x, 3) * 7) * smooth(78, 56, x), 2 + Hash.scene(x, 4) * 1.6, top.(tx)}
    end)
  end

  # What each cell is made of, and its shade: the layers painted in turn,
  # each over the last.
  defp land_cell(x, r, t0, isle, trees, base, tower_top, cottage) do
    y = r + 0.5

    ground(x, y, t0, isle)
    |> trees(x, r, y, trees)
    |> tower(x, y, base, tower_top)
    |> cottage(x, y, cottage)
    |> then(fn {m, shade} -> {m, JSMath.fround(shade)} end)
  end

  defp ground(x, y, t0, _isle) when y >= t0 and y < @horizon + 4 and x < 90 do
    # Rock and scrub, the brow of the slope catching the moon.
    {@land,
     0.2 + 0.45 * fbm(x * 0.35, y * 0.35, 3, 0) + 0.5 * smooth(t0 + 3, t0, y) -
       0.2 * smooth(@horizon - 4, @horizon + 4, y)}
  end

  defp ground(x, y, _t0, isle) when x > 148 and y >= isle and y < @horizon, do: {@isle, 0}
  defp ground(_x, _y, _t0, _isle), do: {@air, 0}

  defp trees(cell, x, r, y, trees) do
    Enum.reduce(trees, cell, fn {tx, th, tw, tb}, acc ->
      dy = y - (tb - th)

      if th >= 1 and dy >= 0 and y < tb + 2 and abs(x + 0.5 - tx) <= dy / th * tw + 0.4,
        do: {@tree, 0.1 + 0.35 * Hash.scene(x * 13 + r, 5) + if(x + 0.5 > tx, do: 0.35, else: 0)},
        else: acc
    end)
  end

  # The tower: tapered, white, lit from the moon on its right; its cap, lantern and roof.
  defp tower({m, shade}, x, y, base, tower_top) do
    dx = x + 0.5 - @lamp_x

    {m, shade} =
      with true <- y >= tower_top and y < base + 2,
           hw = 3 - 1.1 * smooth(base, tower_top, y),
           true <- abs(dx) <= hw do
        {@tower, 0.45 + 0.5 * (dx / hw)}
      else
        false -> {m, shade}
      end

    {m, shade} =
      if y >= tower_top - 1 and y < tower_top + 1 and abs(dx) <= 3.6,
        do: {@cap, 0.55},
        else: {m, shade}

    m = if y >= tower_top - 7 and y < tower_top - 1 and abs(dx) <= 2, do: @lantern, else: m

    if y >= tower_top - 10 and y < tower_top - 7 and abs(dx) <= 2.8 - (tower_top - 7 - y) * 0.8,
      do: {@cap, 0.4},
      else: {m, shade}
  end

  # The keeper's cottage, lit inside.
  defp cottage({m, shade}, x, y, cottage) do
    {m, shade} =
      if x >= 36 and x <= 47 and y >= cottage - 5 and y < cottage + 1 do
        m = if x in [39, 44] and y >= cottage - 4 and y < cottage - 1.5, do: @pane, else: @wall
        {m, 0.3 + 0.4 * (x - 36) / 11}
      else
        {m, shade}
      end

    if y >= cottage - 10 and y < cottage - 5 and
         abs(x + 0.5 - 42) <= 7.5 - (cottage - 5 - y) * 1.2,
       do: {@roof, shade},
       else: {m, shade}
  end

  defp density(x, y) do
    q = fbm(x * 0.008, y * 0.02, 3, @cw * 0.008)
    d = fbm(x * 0.018 + q * 2.4, y * 0.036 + q * 1.1, 5, @cw * 0.018)
    # Heaped mid-sky, thinner overhead, wisps at the horizon.
    d + 0.05 * smooth(8, 22, y) - 0.04 * smooth(10, 0, y) - 0.16 * smooth(36, @horizon - 4, y)
  end

  # Everything about a cell that does not move, worked out as the frame would
  # work it out, so the frame only does what changes. Each term keeps the
  # frame's own operations in the frame's own order, so the bits are upstream's.
  defp static(x, r, {m, shade}, haze, tower_top) do
    y = r + 0.5
    dmx = x + 0.5 - @moon_x
    dmy = y - @moon_y
    dm = :math.sqrt(dmx * dmx + dmy * dmy)
    beam = beam_static(x, r, m, tower_top)

    cond do
      y < @horizon and m == @air ->
        sky_static(x, r, y, dm, haze, beam)

      y >= @horizon and (m == @air or m == @land) and not (m == @land and y < @horizon + 4) ->
        sea_static(x, y, beam)

      m == @land ->
        {:solid, 0.05 + 0.14 * shade, 0.09 + 0.2 * shade, 0.1 + 0.18 * shade, 0.1, beam}

      m == @tree ->
        {:solid, 0.03 + 0.07 * shade, 0.07 + 0.14 * shade, 0.07 + 0.1 * shade, 0.06, beam}

      # A buoy light out on the point, blinking.
      m == @isle and x == 184 and r == 55 ->
        {:buoy, beam}

      m == @isle ->
        {:solid, 0.06, 0.08, 0.15, 0.1, beam}

      m == @tower ->
        {:solid, 0.4 + 0.58 * shade, 0.42 + 0.56 * shade, 0.48 + 0.52 * shade, 0.3, beam}

      m == @cap ->
        {:solid, (0.4 + 0.58 * shade) * 0.7, (0.42 + 0.56 * shade) * 0.66,
         (0.48 + 0.52 * shade) * 0.68, 0.3, beam}

      m == @lantern ->
        {:lantern, beam}

      m == @wall ->
        {:solid, 0.3 + 0.4 * shade, 0.32 + 0.4 * shade, 0.38 + 0.4 * shade, 0.3, beam}

      m == @pane ->
        {:pane, beam}

      m == @roof ->
        {:solid, 0.4, 0.17, 0.14, 0.3, beam}
    end
  end

  # Sky: deep navy up top to a hazy horizon, brighter round the moon.
  defp sky_static(x, r, y, dm, haze, beam) do
    v = y / @horizon
    halo = :math.exp(-dm / 24) * 0.35 + :math.exp(-dm / 9) * 0.45
    # The horizon's last light.
    glow_h = :math.pow(v, 3) * 0.24
    veil = 0.85 + 0.3 * haze

    moon = if dm < 6, do: {0.86 + 0.14 * fbm(x * 0.5, y * 0.5, 2, 0), smooth(6, 5, dm)}

    star =
      if dm >= 6 and Hash.scene(x, r * 3 + 11) > 0.982,
        do:
          {1.5 + Hash.scene(x, r) * 3, Hash.scene(r, x) * 6.28, 1 - halo, smooth(@horizon, 20, y)}

    {:sky, (0.04 + 0.1 * v * v + glow_h * 0.9) * veil + 0.3 * halo,
     (0.07 + 0.13 * v * v + glow_h) * veil + 0.35 * halo,
     (0.17 + 0.2 * v * v + glow_h * 1.1) * veil + 0.42 * halo, 0.15 + 0.85 * smooth(7, 24, dm),
     moon, star, 0.5 + 0.6 * :math.exp(-dm / 30), 0.25 * smooth(30, @horizon, y), beam}
  end

  # Sea: cold, darker toward us, waves stretched along the swell.
  defp sea_static(x, y, beam) do
    v = (y - @horizon) / (@h - @horizon)
    # The moon's road: wider toward us, broken into glints; and the lamp's
    # reflection, warm, under the tower.
    road_w = 3 + (y - @horizon) * 0.55
    road = :math.exp(-:math.pow((x + 0.5 - @moon_x) / road_w, 2))
    lw = 1.3 + (y - @horizon) * 0.22
    refl = :math.exp(-:math.pow((x + 0.5 - @lamp_x) / lw, 2))
    # Surf where the headland meets the water.
    foam =
      if y < @horizon + 8 and x < 90,
        do: smooth(90, 74, x) * smooth(@horizon + 8, @horizon + 3, y)

    haze = :math.exp(-(y - @horizon) / 2.5) * 0.16

    {
      :sea,
      {0.08 - 0.04 * v, 0.13 - 0.06 * v, 0.28 - 0.12 * v},
      road,
      {0.07 * road, 0.09 * road, 0.15 * road},
      refl,
      foam,
      {haze * 0.8, haze * 0.9, haze},
      # The bottom rows thin out into the ground.
      smooth(@h, @h - 26, y),
      beam
    }
  end

  # The lamp lights everything but itself: the cone's falloff across it, the
  # distance from it, and the glow's steady part; and the whole glow for a
  # frame without a flash, which is half of them.
  defp beam_static(_x, _r, m, _tower_top) when m in [@tower, @cap, @lantern], do: nil

  defp beam_static(x, r, _m, tower_top) do
    bx = x + 0.5 - @lamp_x
    by = r + 0.5 - (tower_top - 4)
    spread = 1.4 + abs(bx) * 0.11
    dl = :math.sqrt(bx * bx + by * by)
    steady = :math.exp(-dl / 14) * 0.12
    {:math.exp(-:math.pow(by / spread, 2)), -dl, steady, :math.exp(-dl / 3.5) * 0.5 + steady}
  end

  @impl true
  def frame(state, t, env) do
    # Starts out over the sea.
    beam = t / 8 * :math.pi() * 2 - 0.75
    cb = :math.cos(beam)
    # Pointed at us.
    flash = :math.pow(max(0, :math.sin(beam)), 14) * 2.2
    k = 3.5 + 3 * flash
    lift = 0.5 + 0.6 * flash

    fr = %{
      t: t,
      drift: t * 1.4,
      # The cone's length along each column depends on the column alone.
      cone: List.to_tuple(for x <- 0..(@w - 1), do: cone(x + 0.5 - @lamp_x, cb)),
      # A flash too faint to move the glow's reach or lift leaves the glow as
      # it is without one, worked out in init.
      glow: if(k == 3.5 and lift == 0.5 and not state.exact?, do: :still, else: {k, lift}),
      refl: 0.75 + 0.6 * flash,
      lantern: 0.85 + 0.15 * min(1, flash),
      cover: state.cover,
      lit: state.lit,
      color?: env.color?,
      bounds: state.bounds
    }

    waves = waves(t)
    hot = {fr.cone, fr.glow, {env.color?, if(state.exact?, do: nil, else: state.bounds)}}

    {memo, lut} =
      state.rows
      |> Enum.zip(if state.exact?, do: fresh_memo(), else: state.memo)
      |> Enum.map_reduce(state.lut, fn {{specs, r}, memo}, lut ->
        row(specs, memo, 0, {r, row_data(waves, fr, r), hot}, lut, [])
      end)

    text = Enum.map(memo, &chars/1)
    colors = if env.color?, do: memo |> Enum.map(&colours/1) |> IO.iodata_to_binary()
    {Enum.intersperse(text, ?\n), colors, %{state | lut: lut, memo: memo}}
  end

  defp cone(bx, cb) do
    along = abs(bx) / (abs(cb) * 115 + 1)
    if bx * cb > 0 and along < 1, do: :math.pow(1 - along, 1.8)
  end

  # The sea's noises, each sampled on a lattice whose x part depends on the
  # column alone and y part on the row alone: the swell's two, and the surf's.
  defp waves(t) do
    {field(0.07, t * 0.12, 0.45, -(t * 0.6), @horizon..(@h - 1), @w - 1),
     field(0.2, -(t * 0.25), 0.9, -(t * 1.1), @horizon..(@h - 1), @w - 1),
     field(0.45, -(t * 0.6), 0.8, t * 0.4, @horizon..(@horizon + 7), 89)}
  end

  # Value noise at (x * ax + bx, y * ay + by) for columns 0..last and the
  # given rows: each column's lattice cell and weight, each row's weight and
  # the hashes along its two lattice rows.
  defp field(ax, bx, ay, by, rows, last) do
    cols = for x <- 0..last, do: lattice_at(x * ax + bx)
    {x_min, x_max} = cols |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    ys = for r <- rows, do: lattice_at((r + 0.5) * ay + by)
    {y_min, y_max} = ys |> Enum.map(&elem(&1, 0)) |> Enum.min_max()

    hashes =
      List.to_tuple(
        for yi <- y_min..(y_max + 1) do
          List.to_tuple(for xi <- x_min..(x_max + 1), do: Hash.scene(xi, yi))
        end
      )

    {List.to_tuple(for {xi, u} <- cols, do: {xi - x_min, u}),
     List.to_tuple(
       for {yi, v} <- ys, do: {v, elem(hashes, yi - y_min), elem(hashes, yi - y_min + 1)}
     )}
  end

  defp lattice_at(p) do
    i = floor(p)
    f = p - i
    {i, f * f * (3 - 2 * f)}
  end

  # What a row's cells share this frame. Above the horizon: the clouds'
  # strips, their drift, t and the lantern; below it: the sea's noises (each
  # one's columns, and this row's weight and hashes), t and the reflection.
  defp row_data(_waves, fr, r) when r < @horizon,
    do: {elem(fr.cover, r), elem(fr.lit, r), fr.drift, fr.t, fr.lantern}

  defp row_data({{c1, r1}, {c2, r2}, {c3, r3}}, fr, r) do
    i = r - @horizon
    foam = if i < tuple_size(r3), do: {c3, elem(r3, i)}
    {{c1, elem(r1, i)}, {c2, elem(r2, i)}, foam, fr.t, fr.refl}
  end

  # `noise(x, y, 0)` from its lattice, as `Ascii.Kit.Scene.noise/3` does it.
  defp noise({cols, {v, h0, h1}}, x) do
    {off, u} = elem(cols, x)
    bilerp(elem(h0, off), elem(h0, off + 1), elem(h1, off), elem(h1, off + 1), u, v)
  end

  defp bilerp(a, b, c, d, u, v)
       when is_float(a) and is_float(b) and is_float(c) and is_float(d) and is_float(u) and
              is_float(v),
       do: a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

  defp lerp(a, b, f) when is_float(a) and is_float(b) and is_float(f), do: a + (b - a) * f

  defp chars([]), do: []
  defp chars([{_, _, _, char, _} | cells]), do: [char | chars(cells)]

  defp colours([]), do: []
  defp colours([{_, _, _, _, colour} | cells]), do: [colour | colours(cells)]

  # Each cell gives {r, g, b, its dot, its colour}, which the next frame keeps
  # as a memo: a cell shaded to the same colour (its floor and fade never
  # change) draws the same dot, and, its colour already in the cache, the
  # same colour, since an answer in the cache never changes.
  defp row([], [], _x, _ctx, lut, acc), do: {Enum.reverse(acc), lut}

  defp row([spec | specs], [memo | memos], x, ctx, lut, acc) do
    {cell, lut} = shade(spec, memo, x, ctx, lut)
    row(specs, memos, x + 1, ctx, lut, [cell | acc])
  end

  defp shade({:solid, cr, cg, cb, floor, beam}, memo, x, {r, _, {cone, glow, dot}}, lut) do
    {cr, cg, cb} = light(beam, elem(cone, x), glow, cr, cg, cb)
    dot(cr, cg, cb, floor, 1.0, x, r, memo, dot, lut)
  end

  defp shade({:buoy, beam}, memo, x, {r, data, {cone, glow, dot}}, lut) do
    {cr, cg, cb} =
      if :math.sin(elem(data, 3) * 2.2) > 0.55, do: {1.0, 0.36, 0.3}, else: {0.35, 0.12, 0.1}

    {cr, cg, cb} = light(beam, elem(cone, x), glow, cr, cg, cb)
    dot(cr, cg, cb, 0.1, 1.0, x, r, memo, dot, lut)
  end

  defp shade({:lantern, beam}, memo, x, {r, {_, _, _, _, lantern}, {cone, glow, dot}}, lut) do
    g = float!(lantern)
    {cr, cg, cb} = light(beam, elem(cone, x), glow, g, 0.84 * g, 0.5 * g)
    dot(cr, cg, cb, 0.3, 1.0, x, r, memo, dot, lut)
  end

  defp shade({:pane, beam}, memo, x, {r, {_, _, _, t, _}, {cone, glow, dot}}, lut) do
    g = 0.85 + 0.15 * float!(:math.sin(t * 3 + x))
    {cr, cg, cb} = light(beam, elem(cone, x), glow, g, 0.72 * g, 0.32 * g)
    dot(cr, cg, cb, 0.3, 1.0, x, r, memo, dot, lut)
  end

  defp shade({:sky, cr, cg, cb, cloud, moon, star, near, rim, beam}, memo, x, ctx, lut) do
    {r, {cover, lit, drift, t, _}, {cone, glow, dot}} = ctx
    {i0, i1, fx} = drift(x, drift)
    # A break in the cloud round the moon.
    c = lerp(elem(cover, i0), elem(cover, i1), fx) * cloud

    {cr, cg, cb} =
      cond do
        moon != nil -> moon({cr, cg, cb}, c, moon)
        star != nil and c < 0.05 -> star({cr, cg, cb}, star, t)
        true -> {cr, cg, cb}
      end

    {cr, cg, cb} =
      if c > 0.01,
        do: cloud({cr, cg, cb}, c, lerp(elem(lit, i0), elem(lit, i1), fx), near, rim),
        else: {cr, cg, cb}

    {cr, cg, cb} = light(beam, elem(cone, x), glow, cr, cg, cb)
    dot(cr, cg, cb, 0.15, 1.0, x, r, memo, dot, lut)
  end

  defp shade(
         {:sea, {sr, sg, sb}, road, {gr, gg, gb}, refl, foam, {hr, hg, hb}, fade, beam},
         memo,
         x,
         {r, {n1, n2, n3, _t, lamp}, {cone, glow, dot}},
         lut
       ) do
    w = 0.6 * noise(n1, x) + 0.4 * noise(n2, x)
    {cr, cg, cb} = swell(w, {sr, sg, sb}, road, {gr, gg, gb}, refl, float!(lamp))
    # Surf where the headland meets the water.
    {cr, cg, cb} = if foam, do: surf({cr, cg, cb}, foam, noise(n3, x)), else: {cr, cg, cb}
    {cr, cg, cb} = light(beam, elem(cone, x), glow, cr + hr, cg + hg, cb + hb)
    dot(cr, cg, cb, 0.18, fade, x, r, memo, dot, lut)
  end

  # Where the clouds' wrapping strip is under column x: its two cells and the
  # weight between them.
  defp drift(x, drift) when is_float(drift) do
    sx = x + drift
    ix = floor(sx)
    {rem(ix, @cw), rem(ix + 1, @cw), sx - ix}
  end

  # The moon, dimmed where cloud crosses it.
  defp moon({cr, cg, cb}, c, {face, edge})
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(c) and is_float(face) and
              is_float(edge) do
    a = (1 - c * 0.8) * edge
    {mix(cr, 0.96 * face, a), mix(cg, 0.97 * face, a), mix(cb, 1.0 * face, a)}
  end

  defp star({cr, cg, cb}, {speed, phase, dark, low}, t)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(dark) and is_float(low) do
    tw = 0.6 + 0.4 * float!(:math.sin(t * speed + phase))
    s = (0.5 + 0.5 * tw) * dark * low
    {max(cr, s * 0.92), max(cg, s * 0.94), max(cb, s)}
  end

  # Shadow slate, through moonlit grey, to a silver rim near the moon; low
  # cloud is lit from below by the horizon and stays hazy.
  defp cloud({cr, cg, cb}, c, l, near, rim)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(c) and is_float(l) and
              is_float(near) and is_float(rim) do
    b = clamp(l * near + rim)

    {kr, kg, kb} =
      if b < 0.5,
        do: {mix(0.1, 0.36, b * 2), mix(0.13, 0.42, b * 2), mix(0.25, 0.58, b * 2)},
        else:
          {mix(0.36, 0.95, (b - 0.5) * 2), mix(0.42, 0.96, (b - 0.5) * 2),
           mix(0.58, 1.0, (b - 0.5) * 2)}

    a = min(1.0, c * 1.1)
    {mix(cr, kr, a), mix(cg, kg, a), mix(cb, kb, a)}
  end

  # Sea: cold, darker toward us, waves stretched along the swell; the moon's
  # road broken into glints, and the lamp's reflection.
  defp swell(w, {sr, sg, sb}, road, {gr, gg, gb}, refl, lamp)
       when is_float(w) and is_float(sr) and is_float(sg) and is_float(sb) and is_float(road) and
              is_float(gr) and is_float(gg) and is_float(gb) and is_float(refl) and
              is_float(lamp) do
    swell = 0.45 + 0.95 * w
    glint = smooth(0.5, 0.8, w) * road
    refl = refl * smooth(0.45, 0.8, w) * lamp

    {sr * swell + (0.95 * glint + gr) + refl, sg * swell + (0.95 * glint + gg) + 0.72 * refl,
     sb * swell + (0.95 * glint + gb) + 0.32 * refl}
  end

  defp surf({cr, cg, cb}, edge, n)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(edge) and is_float(n) do
    foam = smooth(0.5, 0.85, n) * edge
    {cr + 0.65 * foam, cg + 0.7 * foam, cb + 0.75 * foam}
  end

  # The beam: a soft cone from the lamp to one side, shortened as it turns
  # toward or away from us, and a glow that flares when it faces us.
  defp light(nil, _cone, _glow, cr, cg, cb), do: {cr, cg, cb}

  defp light({across, neg_dl, steady, still}, cone, glow, cr, cg, cb)
       when is_float(across) and is_float(neg_dl) and is_float(steady) and is_float(still) and
              is_float(cr) and is_float(cg) and is_float(cb) do
    {cr, cg, cb} =
      if is_float(cone) do
        b = cone * across * 0.85
        {cr + b, cg + b * 0.84, cb + b * 0.5}
      else
        {cr, cg, cb}
      end

    g = glow(glow, neg_dl, steady, still)
    {cr + g, cg + g * 0.82, cb + g * 0.5}
  end

  defp glow(:still, _neg_dl, _steady, still), do: still

  defp glow({k, lift}, neg_dl, steady, _still) when is_float(k) and is_float(lift),
    do: float!(:math.exp(neg_dl / k)) * lift + steady

  # Dot size from brightness, dithered. Then the colour makes up what the dot
  # size could not: a small dot is drawn brighter and a large one dimmer, so a
  # gradient stays smooth across the dither's steps. A memo of the same colour
  # already has both.
  defp dot(cr, cg, cb, floor, fade, x, r, memo, {color?, bounds}, lut)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(floor) and
              is_float(fade) do
    case memo do
      {^cr, ^cg, ^cb, _char, colour} when colour != nil or not color? ->
        {memo, lut}

      _ ->
        peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
        bayer = elem(@bayer, band(r, 3) * 4 + band(x, 3))

        case settle(peak, floor, fade, bayer, color?, bounds) do
          {step, nil} ->
            {{cr, cg, cb, elem(@dots, step), nil}, lut}

          # The exact path asks the palette itself.
          {step, want} when is_float(want) and bounds == nil ->
            s = (0.3 + 0.7 * want) / peak
            {i, lut} = Palette.nearest(lut, clamp(cr * s), clamp(cg * s), clamp(cb * s))
            {{cr, cg, cb, elem(@dots, step), i}, lut}

          {step, want} when is_float(want) ->
            {i, lut} = nearest(lut, {cr, cg, cb}, (0.3 + 0.7 * want) / peak)
            {{cr, cg, cb, elem(@dots, step), i}, lut}

          {step, {low, high}} ->
            {i, lut} = between(lut, {cr, cg, cb}, peak, step, {low, high}, {floor, fade})
            {{cr, cg, cb, elem(@dots, step), i}, lut}
        end
    end
  end

  # The colour for a weight known only to lie between the weights of two
  # levels: its cache entry, when both ends land on the same one and it is
  # already answered; otherwise the colour from the exact level.
  defp between(lut, rgb, peak, step, {low, high}, {floor, fade}) do
    lo = (0.3 + 0.7 * want(step, low)) / peak
    hi = (0.3 + 0.7 * want(step, high)) / peak
    key = key(rgb, lo)

    with true <- key == key(rgb, hi), {:ok, i} <- cached(lut, key) do
      {i, lut}
    else
      _ ->
        level = level(float!(:math.pow(peak, 0.85)), floor, fade)
        nearest(lut, rgb, (0.3 + 0.7 * want(step, level)) / peak)
    end
  end

  # `Ascii.Kit.Palette.nearest/4` for the colour times s, answered here
  # when the cache has it: the key is the palette cache's own, the colour's
  # step on each axis of its 32-step cube.
  defp nearest(lut, {cr, cg, cb} = rgb, s) do
    case cached(lut, key(rgb, s)) do
      {:ok, i} -> {i, lut}
      :error -> Palette.nearest(lut, clamp(cr * s), clamp(cg * s), clamp(cb * s))
    end
  end

  defp cached({_palette, answers}, key) do
    case answers do
      %{^key => i} -> {:ok, i}
      _ -> :error
    end
  end

  defp key({cr, cg, cb}, s)
       when is_float(cr) and is_float(cg) and is_float(cb) and is_float(s),
       do: bsl(cube(clamp(cr * s)), 10) ||| bsl(cube(clamp(cg * s)), 5) ||| cube(clamp(cb * s))

  defp cube(v) when is_float(v), do: min(31, trunc(v * 31.99))

  defp level(p, floor, fade) when is_float(p) and is_float(floor) and is_float(fade),
    do: clamp(floor + (1 - floor) * p * 0.95) * fade

  defp step(level, bayer) when is_float(level) and is_float(bayer),
    do: max(0, min(3, js_round(level * 3 + bayer)))

  defp want(0, _level), do: 0.0
  defp want(step, level) when is_float(level), do: min(1.0, (level + 0.06) / elem(@cover, step))

  # The dot's step and the weight of its colour (nil without colour). Both
  # rise with `Math.pow(peak, 0.85)`, so where they are the same at both ends
  # of that power's bounds they need not wait for it; where only the step is,
  # the weight comes back as the levels at the two ends.
  defp settle(peak, floor, fade, bayer, color?, bounds)
       when is_tuple(bounds) and peak < @pow_top do
    {lo, hi} = elem(bounds, trunc(peak * @grain))
    low = level(lo, floor, fade)
    step = step(low, bayer)

    high = level(hi, floor, fade)

    cond do
      step != step(high, bayer) -> exact(peak, floor, fade, bayer, color?)
      not color? -> {step, nil}
      step == 0 -> {0, 0.0}
      want(step, low) == 1 -> {step, 1.0}
      true -> {step, {low, high}}
    end
  end

  defp settle(peak, floor, fade, bayer, color?, _bounds),
    do: exact(peak, floor, fade, bayer, color?)

  defp exact(peak, floor, fade, bayer, color?) do
    level = level(float!(:math.pow(peak, 0.85)), floor, fade)
    step = step(level, bayer)
    {step, if(color?, do: want(step, level))}
  end

  # Bounds on `Math.pow(peak, 0.85)` for a peak in [i, i + 1) / GRAIN: each
  # end's power, widened by far more than the error of a libm's pow (under an
  # ulp), so the power of any peak inside lies between them.
  defp pow_bounds do
    List.to_tuple(
      for i <- 0..(@pow_top * @grain - 1) do
        {:math.pow(i / @grain, 0.85) * (1 - 1.0e-12),
         :math.pow((i + 1) / @grain, 0.85) * (1 + 1.0e-12)}
      end
    )
  end
end
