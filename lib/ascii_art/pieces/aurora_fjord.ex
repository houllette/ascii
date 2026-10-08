defmodule AsciiArt.Pieces.AuroraFjord do
  @moduledoc """
  Aurora curtains rippling over a still fjord, a cabin lit on the shore.

  Curtains of aurora ripple over a fjord between snowy mountains. The still
  water holds a broken shimmer of them, and a red cabin on the far shore
  keeps its lamps lit.

  Shaded in colour per cell on a square grid, then drawn as a halftone: dot
  size is brightness, ordered-dithered, in the palette colour nearest its
  hue. The land is built once; each frame shades the sky, then mirrors it
  into the water.

  Ported from `src/pieces/aurora-fjord.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Palette
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "aurora fjord",
    category: :scenes,
    note: "aurora curtains rippling over a still fjord, a cabin lit on the shore",
    cols: 200,
    rows: 100,
    cell: 1,
    fps: 15,
    ground: "#05080f",
    palette: [
      "#0b1322",
      "#101b30",
      "#16243f",
      "#1e3050",
      "#2a3f63",
      "#0e3a33",
      "#11573f",
      "#167a4c",
      "#22a05c",
      "#3ccb73",
      "#7cf0a0",
      "#c8ffdc",
      "#0f5f5c",
      "#16877f",
      "#2cb5a6",
      "#7fe6d6",
      "#2a1f52",
      "#432b78",
      "#6a3c9f",
      "#9558c6",
      "#c48ae4",
      "#363a72",
      "#4f5596",
      "#1b4f63",
      "#1a2236",
      "#283350",
      "#3b4a6e",
      "#566a92",
      "#7d91b8",
      "#a9bad9",
      "#d6e0f2",
      "#9fc9cf",
      "#0f1a1c",
      "#173128",
      "#24493a",
      "#4a1517",
      "#7c2420",
      "#b23a2a",
      "#d65aa8",
      "#ffd27c",
      "#ffb04a",
      "#fff2c4",
      "#eef3ff"
    ]
  }

  @w 200
  @h 100
  # The waterline.
  @wl 62
  @dots {" ", "·", "•", "●"}
  @cover {0, 0.3, 0.6, 1}
  @bayer [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
         |> Enum.map(&(&1 / 16 - 0.47))
         |> List.to_tuple()

  @air 0
  @near 1
  @far 2
  @shore 3
  @wall 4
  @roof 5
  @pane 6
  @tree 7
  @door 8

  # The cabin's walls, x from and to; its panes, door, and lamps (pane
  # centres and their strength).
  @cab0 142
  @cab1 161
  @panes [{145, 148}, {156, 159}]
  @door0 150
  @door1 152
  @lamps [{147, 1}, {158, 0.8}]
  @cab_base @wl - 2.2
  @eave @cab_base - 7

  # Ranges as tent peaks {x, height, slope}, roughened.
  @left [{25, 38, 1.3}, {6, 29, 0.9}, {50, 25, 1.0}, {72, 13, 0.6}]
  @right [{172, 30, 1.15}, {194, 24, 0.85}, {151, 16, 1.0}, {212, 22, 0.6}]
  @distant [{100, 10, 0.5}, {119, 12, 0.55}, {86, 7, 0.45}, {134, 8, 0.5}]

  # The curtains' rays, sampled every quarter column.
  @rays 4 * @w

  @gamma 0.85
  @power_lo -20
  @margin 1.0e-8
  @f32_margin 1.0e-11
  @mul_lo band(1_274_126_177, 0xFFFF)

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
            key: 3,
            cube: 1,
            round_js: 1,
            power: 2,
            sure?: 1,
            wave: 2}
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

  defp range(x, peaks, seed, rough) do
    {m, px} =
      Enum.reduce(peaks, {-99, 0}, fn {cx, h, s}, {m, px} ->
        v = h - abs(x - cx) * s
        if v > m, do: {v, cx}, else: {m, px}
      end)

    j = rough * (fbm(x * 0.09, seed, 3) - 0.5) + rough * 0.45 * (noise(x * 0.45, seed + 5) - 0.5)
    {m + j * min(1, max(0, m) / 6), px}
  end

  defp shore_top(x),
    do: @wl - 2.2 * smooth(134, 140, x) * smooth(178, 168, x) - 0.6 * noise(x * 0.3, 2)

  @impl true
  def init(_options) do
    # --- the land, built once ---------------------------------------------
    tops =
      for x <- 0..(@w - 1) do
        {hl, pl} = range(x + 0.5, @left, 3.1, 4)
        {hr, pr} = range(x + 0.5, @right, 7.7, 4)
        {hd, _} = range(x + 0.5, @distant, 11.3, 2.2)

        {f32(@wl - max(max(hl, hr), 0)), f32(if(hl > hr, do: pl, else: pr)),
         f32(@wl - max(hd, 0))}
      end

    land =
      for {{near_top, peak_x, far_top}, x} <- Enum.with_index(tops),
          r <- 0..(@wl - 1),
          into: %{},
          do: {r * @w + x, land_cell(x, r, near_top, peak_x, far_top)}

    land = land |> treeline() |> cabin() |> shelf_trees()

    mats =
      List.to_tuple(
        for r <- 0..(@wl - 1) do
          List.to_tuple(for x <- 0..(@w - 1), do: elem(Map.fetch!(land, r * @w + x), 0))
        end
      )

    sky =
      for r <- 0..(@wl - 1) do
        y = r + 0.5
        cells = for x <- 0..(@w - 1), do: sky_static(x, r, Map.fetch!(land, r * @w + x))
        # Airglow on the horizon; curtain B thinning out toward the top; the
        # stars fading into it.
        {r, y, {:math.exp(-(@wl - y) / 10), smooth(0, 8, y), smooth(@wl - 2, 30, y)}, cells}
      end

    water =
      for r <- @wl..(@h - 1) do
        y = r + 0.5
        dw = y - @wl
        deep = mix(1, 0.45, dw / (@h - @wl))
        # The mirror row: Math.round(0.4 * sin(...)) is always 0.
        ry = @wl - 1 - (r - @wl)

        row =
          {r, y, dw, deep, smooth(@h + 3, @h - 12, y), hash(r, 404) < 0.3, ry, 0.5 + dw * 0.12,
           r * 1.3}

        {row, for(x <- 0..(@w - 1), do: water_static(x, r, dw))}
      end

    curtains =
      List.to_tuple(
        for x <- 0..(@w - 1) do
          u = x / @w

          {5 + 40 * :math.pow(:math.sin(min(1, u / 0.6) * :math.pi() / 2), 1.5) -
             13 * smooth(0.6, 0.95, u), smooth(0.0, 0.2, u) * smooth(0.98, 0.72, u),
           smooth(0.45, 0.7, u) * smooth(1.05, 0.85, u)}
        end
      )

    %{
      sky: sky,
      water: water,
      mats: mats,
      curtains: curtains,
      power: power_table(@gamma),
      ray_powers: {power_table(2.4), power_table(2.2)},
      lut: Palette.nearest_lut(@meta.palette),
      # Set only by the tests: every shortcut a frame takes (the fast powers
      # and the margins that guard them, the curtain terms skipped where they
      # add exactly nothing, the water's shared lattice) is then taken the
      # long way, so the two can be checked against each other.
      exact?: false
    }
  end

  defp land_cell(x, r, near_top, peak_x, far_top) do
    y = r + 0.5

    cell =
      cond do
        y >= near_top -> near_cell(x, r, y, near_top, peak_x)
        y >= far_top -> far_cell(x, y, far_top)
        true -> {@air, 0.0, 0.0, 0.0, 0.0, 0.0}
      end

    # The shelf the cabin stands on, snowed over.
    if x > 132 and x < 180 and y >= shore_top(x) do
      f = 0.6 + 0.3 * fbm(x * 0.3, y * 0.5, 2)
      {@shore, f32(0.26 * f), f32(0.3 * f), f32(0.42 * f), f32(0.4), 0.0}
    else
      cell
    end
  end

  defp near_cell(x, r, y, near_top, px) do
    side = x + 0.5 - px
    depth = y - near_top
    height = @wl - near_top
    # Faces turned toward the fjord catch the aurora; the ridge between the
    # faces wanders as it comes down from the peak.
    ridge = px + (depth + 1) * 0.6 * (noise(y * 0.1, px) - 0.5)
    inward = if px < 100, do: 1, else: -1
    face = smooth(-4, 4, (x + 0.5 - ridge) * inward)
    # Ribs and couloirs running down the fall line, each with a lit side.
    u = x + depth * 0.45 * if(side == 0, do: 1, else: JSMath.sign(side))
    rib = fn v -> fbm(v * 0.13, px * 0.37, 3) end
    grad = (rib.(u + 1) - rib.(u - 1)) * 7 * inward
    # The snow reaches further down the ribs than the couloirs, in fingers.
    reach = 3 + height * (0.62 + 0.42 * rib.(u + 40))
    streak = smooth(0.56, 0.64, fbm(u * 0.32, y * 0.035 + px, 3)) * smooth(1, 5, depth)
    # A stand of spruce climbing the slope behind the cabin, jagged on top.
    cx = x + 0.5 - 152

    wood =
      @wl - 18.5 + 9 * (cx / 19 * (cx / 19)) + 1.5 * (noise(x * 0.7, 9) - 0.5) -
        2.6 * hash(x, 77) * if(band(x, 1) == 1, do: 1, else: 0.3)

    snow =
      smooth(reach + 1.6, reach - 1.6, depth) * (1 - smooth(@wl - 3, @wl - 0.5, y)) *
        (1 - 0.5 * streak)

    lit = clamp(0.35 + 0.55 * face + grad * 0.5)

    if y > wood and cx > -14 - 2 * hash(r, 3) and cx < 13 + 2 * hash(r, 4) do
      h = hash(x * 13 + r, 5)

      {@tree, f32(0.02 + 0.03 * h), f32(0.045 + 0.045 * h), f32(0.06 + 0.04 * h), f32(0.05),
       f32(smooth(wood + 1.6, wood + 0.2, y) * (0.7 + 0.3 * h))}
    else
      # Blue-grey rock below the snow, a little lighter on the lit faces.
      rv = 0.75 + 0.5 * fbm(x * 0.4, y * 0.4, 2)
      rr = (0.05 + 0.03 * lit) * rv
      rg = (0.065 + 0.035 * lit) * rv
      rb = (0.11 + 0.05 * lit) * rv
      s = 0.34 + 0.66 * :math.pow(lit, 1.5)

      {@near, f32(mix(rr, 0.62 * s + 0.04, snow)), f32(mix(rg, 0.7 * s + 0.05, snow)),
       f32(mix(rb, 0.86 * s + 0.09, snow)), f32(snow * (0.25 + 0.75 * lit) + 0.06),
       f32(smooth(2.2, 0.3, depth) * 0.5)}
    end
  end

  defp far_cell(x, y, far_top) do
    depth = y - far_top
    snow = smooth(0.5, 0.62, fbm(x * 0.18, y * 0.25, 3) * 0.6 + (1 - depth / 7) * 0.55)
    lit = 0.5 + 0.3 * (noise(x * 0.25, y * 0.1) - 0.5)

    {@far, f32(mix(0.075, 0.22 * lit + 0.12, snow)), f32(mix(0.1, 0.27 * lit + 0.15, snow)),
     f32(mix(0.17, 0.36 * lit + 0.24, snow)), f32(0.2 + 0.3 * snow), 0.0}
  end

  # A spruce: tiers widening down to its base at `tb`, lit from the upper
  # left where the aurora is. `guard` names the cells it must not cover.
  defp spruce(land, tx, th, tw, tb, guard) do
    for r <- max(0, floor(tb - th))..(@wl - 1)//1,
        y = r + 0.5,
        dy = y - (tb - th),
        dy >= 0 and y < tb + 0.5,
        tier = (dy + th * 0.3) / 1.8,
        w = dy / th * tw * (0.7 + 0.45 * (tier - floor(tier))) + 0.35,
        x <- max(0, floor(tx - tw - 1))..(@w - 1)//1,
        x <= tx + tw + 1,
        ex = x + 0.5 - tx,
        abs(ex) <= w,
        reduce: land do
      land ->
        k = r * @w + x

        if guarded?(guard, elem(Map.fetch!(land, k), 0)) do
          land
        else
          h = hash(x * 13 + r, 5)
          s = if ex < 0, do: 0.7, else: 0.3
          side = if ex < 0 and ex < -w + 1, do: 0.45 * smooth(th, 0, dy), else: 0

          Map.put(
            land,
            k,
            {@tree, f32(0.02 + 0.03 * s * h), f32(0.04 + 0.05 * s), f32(0.055 + 0.045 * s),
             f32(0.05), f32(max(smooth(1.6, 0.2, dy), side))}
          )
        end
    end
  end

  defp guarded?(nil, _m), do: false
  defp guarded?(:solid, m), do: m in [@wall, @roof, @pane, @door, @shore]
  defp guarded?(:cabin, m), do: m in [@wall, @roof, @pane, @door]

  # A spruce treeline along the foot of both ranges, open where the fjord
  # runs in.
  defp treeline(land) do
    Stream.unfold(-1, fn x ->
      if x < @w + 2, do: {x, x + (2 + 2.2 * hash(floor(x * 7), 21))}
    end)
    |> Enum.reduce(land, fn x, land ->
      open = smooth(96, 80, x) + smooth(122, 136, x)
      shelf? = x > 132 and x < 180

      th =
        (3.2 + hash(floor(x * 3), 5) * 3 + if(hash(floor(x * 5), 8) > 0.7, do: 2.4, else: 0)) *
          min(1, open) * if(shelf?, do: 0.7, else: 1)

      if open > 0.05 and not (x > 136 and x < 166) and th > 1.5 do
        tb = if shelf?, do: shore_top(x) - 0.4, else: @wl + 0.3

        spruce(
          land,
          x + hash(floor(x), 2),
          th,
          1 + hash(floor(x), 4) * 0.6,
          tb,
          if(shelf?, do: :solid)
        )
      else
        land
      end
    end)
  end

  # The cabin: red boards, a snowed roof, two warm panes, a door, a chimney.
  defp cabin(land) do
    for r <- 0..(@wl - 1), x <- (@cab0 - 3)..(@cab1 + 3), reduce: land do
      land ->
        k = r * @w + x
        cell = land |> Map.fetch!(k) |> walls(x, r) |> roof(x, r) |> chimney(x, r)
        Map.put(land, k, cell)
    end
  end

  defp walls({_, _, _, _, rec, _} = cell, x, r) do
    y = r + 0.5

    if x >= @cab0 and x <= @cab1 and y >= @eave and y < @cab_base + 0.5 do
      boards = if band(r, 1) == 1, do: 0.82, else: 1
      s = (0.5 + 0.5 * ((@cab1 - x) / (@cab1 - @cab0))) * boards

      pane? =
        Enum.any?(@panes, fn {a, b} ->
          x >= a and x <= b and y >= @eave + 1.5 and y < @cab_base - 2
        end)

      cond do
        x >= @door0 and x <= @door1 and y >= @eave + 1.5 ->
          {@door, f32(0.16), f32(0.06), f32(0.05), rec, 0.0}

        pane? ->
          {@pane, f32(0.7 * s), f32(0.14 * s), f32(0.11 * s), rec, 0.0}

        true ->
          {@wall, f32(0.7 * s), f32(0.14 * s), f32(0.11 * s), rec, 0.0}
      end
    else
      cell
    end
  end

  defp roof(cell, x, r) do
    y = r + 0.5
    cx = (@cab0 + @cab1 + 1) / 2
    half = 12.5 - (@eave - y) * 1.45

    if y >= @eave - 8 and y < @eave and abs(x + 0.5 - cx) <= half do
      s = 0.78 + 0.22 * ((cx - x - 0.5) / 12)

      if y < @eave - 1,
        do: {@roof, f32(0.78 * s), f32(0.84 * s), f32(0.96 * s), f32(0.5), 0.0},
        else: {@roof, f32(0.12), f32(0.05), f32(0.06), 0.0, 0.0}
    else
      cell
    end
  end

  defp chimney({_, _, _, _, rec, _} = cell, x, r) do
    y = r + 0.5
    chim = @cab1 - 5

    if x >= chim and x <= chim + 1 and y >= @eave - 8.5 and y < @eave - 4 do
      s = if x == chim, do: 1, else: 0.55
      {@wall, f32(0.2 * s), f32(0.21 * s), f32(0.27 * s), rec, 0.0}
    else
      cell
    end
  end

  # A few spruce on the shelf, beside the cabin.
  defp shelf_trees(land) do
    Enum.reduce([{134, 7}, {137.8, 10}, {166.5, 9}, {170, 6}, {174.5, 8}], land, fn {tx, th},
                                                                                    land ->
      spruce(land, tx, th, 2.2, shore_top(tx) + 0.5, :cabin)
    end)
  end

  # Everything about a cell above the waterline that does not move.
  defp sky_static(x, r, {m, sr, sg, sb, rec, rim}) do
    bayer = elem(@bayer, band(r, 3) * 4 + band(x, 3))
    lamp = lamp_land(x, r, m)

    if m == @air do
      y = r + 0.5
      v = y / @wl
      # The sky's unevenness and its stars.
      hz = 0.85 + 0.3 * f32(fbm(x * 0.04, r * 0.07, 3))
      h = hash(x, r + 101)

      star =
        if h > 0.986, do: {f32(0.35 + (h - 0.986) * 45), 1.3 + 3 * hash(x, r), 6.28 * hash(r, x)}

      {:air, x, bayer, (0.025 + 0.03 * v * v) * hz, (0.04 + 0.07 * v * v) * hz,
       (0.1 + 0.11 * v * v) * hz, star, lamp}
    else
      floor =
        cond do
          m == @near -> 0.05
          m == @tree -> 0.04
          true -> 0.06
        end

      {:land, x, bayer, m, sr, sg, sb, rec, rim, lamp, floor}
    end
  end

  # The warm light the panes throw on the snow and the air around them.
  defp lamp_land(_x, _r, m) when m in [@pane, @wall, @roof, @door], do: 0.0

  defp lamp_land(x, r, m) do
    g =
      Enum.reduce(@lamps, 0, fn {lx, s}, g ->
        wx = x + 0.5 - lx
        wy = r + 0.5 - (@cab_base - 2.5)
        d = :math.sqrt(wx * wx * 0.6 + wy * wy * 2.2)
        g + s * :math.exp(-d / 5.5) * 0.6
      end)

    k =
      cond do
        m == @air -> 0.3
        m == @tree -> 0.4
        true -> 0.75 + 0.5 * hash(x, r + 31)
      end

    f32(g * k)
  end

  defp water_static(x, r, dw) do
    bayer = elem(@bayer, band(r, 3) * 4 + band(x, 3))
    # The lamplight laid on the water as a broken golden road.
    road =
      if dw < 14 and x > 138 and x < 166 do
        for {lx, _s} <- @lamps do
          lw = 1 + dw * 0.1
          q = (x + 0.5 - lx) / lw
          :math.exp(-q * q) * :math.exp(-dw / 8)
        end
        |> List.to_tuple()
      end

    {x, bayer, road}
  end

  @impl true
  def frame(state, t, env) do
    ray_powers = if state.exact?, do: {{:exact, 2.4}, {:exact, 2.2}}, else: state.ray_powers
    {cols, rays_a, rays_b} = curtains(state.curtains, t, ray_powers)
    flick = 0.92 + 0.05 * :math.sin(t * 2.3) + 0.03 * :math.sin(t * 7.1)
    fr = {t, flick, rays_a, rays_b, state.exact?}
    acc = {<<>>, <<>>, state.lut, env.color?, if(state.exact?, do: :exact, else: state.power)}

    # --- sky and land -------------------------------------------------------
    {shaded, acc} =
      Enum.map_reduce(state.sky, acc, fn {r, y, row, cells}, acc ->
        {shaded, acc} = sky_cells(cells, r, y, row, cols, fr, [], acc)
        {List.to_tuple(:lists.reverse(shaded)), newline(acc)}
      end)

    shaded = List.to_tuple(shaded)

    # --- the water ----------------------------------------------------------
    {waves, base} = wave_columns(t * 0.05, state.exact?)

    {text, colors, lut, color?, _} =
      Enum.reduce(state.water, acc, fn {row, cells}, acc ->
        {r, _, _, _, _, _, ry, _, _} = row

        mirror =
          {elem(shaded, ry), elem(shaded, ry - 1), elem(shaded, ry - 2), elem(state.mats, ry),
           waves, wave_row(base, r * 0.55 - t * 0.35)}

        acc = water_cells(cells, row, mirror, fr, acc)
        if r < @h - 1, do: newline(acc), else: acc
      end)

    {text, if(color?, do: colors), %{state | lut: lut}}
  end

  defp newline({text, colors, lut, color?, power}),
    do: {<<text::binary, ?\n>>, colors, lut, color?, power}

  # --- the curtains -----------------------------------------------------------
  defp curtains(static, t, powers) do
    a =
      for x <- 0..(@w - 1) do
        {s0, ka, kb} = elem(static, x)

        # The main curtain sweeps down from the upper left, low over the
        # fjord, and lifts again to the right; ripples travel along it and
        # fold it. A fainter curtain behind, higher up, on the right.
        base_a =
          f32(
            s0 + 2.6 * :math.sin(x * 0.07 - t * 0.55) +
              1.4 * :math.sin(x * 0.17 + t * 0.9 + 1.3) + 2.2 * :math.sin(x * 0.22 + t * 1.2) +
              4 * (fbm(x * 0.015 + t * 0.03, 4.2, 2) - 0.5)
          )

        {base_a, f32(11 + 8 * fbm(x * 0.03 - t * 0.05, 1.7, 2)),
         f32(ka * (0.4 + 0.8 * fbm(x * 0.022 - t * 0.07, 8.8, 3))),
         f32(14 + 4 * :math.sin(x * 0.035 + t * 0.3 + 2) + 1.6 * :math.sin(x * 0.11 - t * 0.7)),
         f32(kb * (0.25 + 0.5 * fbm(x * 0.03 + t * 0.05, 3.3, 2)))}
      end
      |> List.to_tuple()

    cols =
      for x <- 0..(@w - 1) do
        {base_a, tall_a, env_a, base_b, env_b} = elem(a, x)
        bend = abs(elem(elem(a, min(@w - 1, x + 1)), 0) - elem(elem(a, max(0, x - 1)), 0))

        # The aurora's light falling on the land below.
        s =
          Enum.reduce(-24..24//6, 0, fn d, s ->
            {_, _, ea, _, eb} = elem(a, min(@w - 1, max(0, x + d)))
            s + (ea + 0.4 * eb)
          end)

        {base_a, tall_a, env_a, base_b, env_b, bend, f32(s / 9)}
      end
      |> List.to_tuple()

    {power_a, power_b} = powers

    rays_a =
      List.to_tuple(
        for i <- 0..(@rays + 1) do
          u = i / 4
          ray_store(0.14, fbm(u * 0.6 + t * 0.35, t * 0.12, 3), power_a, 2.5)
        end
      )

    rays_b =
      List.to_tuple(
        for i <- 0..(@rays + 1) do
          u = i / 4
          ray_store(0.1, fbm(u * 0.45 - t * 0.2, 5 + t * 0.1, 3), power_b, 2.0)
        end
      )

    {cols, rays_a, rays_b}
  end

  # base + pow(m, gamma) * k, as its Float32Array stores it. Math.pow is
  # slow, so power/2 finds it first, within 1e-13; a value at least 1e-11
  # from where the store would round the other way stores what upstream's
  # does, and otherwise it is worked out again with :math.pow.
  defp ray_store(base, m, {:exact, gamma}, k), do: f32(base + :math.pow(m, gamma) * k)

  defp ray_store(base, m, {gamma, _, _, _, _, _} = power, k) do
    v = base + power(m, power) * k
    if sure?(v), do: f32(v), else: f32(base + :math.pow(m, gamma) * k)
  end

  # Whether every value within 1e-11 of v stores the same in a Float32Array.
  defp sure?(v), do: f32(v - @f32_margin) == f32(v + @f32_margin)

  defp ray(arr, u) do
    s = u * 4
    i = floor(s)
    f = s - i
    i = rem(rem(i, @rays) + @rays, @rays)
    a = elem(arr, i)
    a + (elem(arr, i + 1) - a) * f
  end

  defp sky_cells([], _r, _y, _row, _cols, _fr, shaded, acc), do: {shaded, acc}

  defp sky_cells([cell | cells], r, y, row, cols, fr, shaded, acc) do
    x = elem(cell, 1)
    {cr, cg, cb} = shade(cell, r, y, row, elem(cols, x), fr)
    {_, flick, _, _, _} = fr
    lg = lamp(cell) * flick

    {cr, cg, cb} =
      if lg > 0, do: {cr + lg, cg + lg * 0.62, cb + lg * 0.26}, else: {cr, cg, cb}

    c = {f32(cr), f32(cg), f32(cb)}
    {cr, cg, cb} = c
    floor = if elem(cell, 0) == :air, do: 0.1, else: elem(cell, 10)
    acc = dot(cr, cg, cb, floor, 1, elem(cell, 2), acc)
    sky_cells(cells, r, y, row, cols, fr, [c | shaded], acc)
  end

  defp lamp({:air, _, _, _, _, _, _, lamp}), do: lamp
  defp lamp({:land, _, _, _, _, _, _, _, _, lamp, _}), do: lamp

  defp shade({:air, x, _bayer, cr, cg, cb, star, _lamp}, _r, y, row, col, fr) do
    {base_a, tall_a, env_a, base_b, env_b, bend, light_x} = col
    {t, _flick, rays_a, rays_b, exact?} = fr
    {glow, high, low} = row
    {cr, cg, cb, a} = curtain_a(base_a - y, x, tall_a, env_a, bend, rays_a, cr, cg, cb, exact?)
    {cr, cg, cb, a} = curtain_b(base_b - y, x, env_b, high, rays_b, cr, cg, cb, a, exact?)
    # A little glow round the curtain, kept tight under the hem so the hem
    # reads as an edge over dark sky.
    below = y - base_a

    {cr, cg, cb} =
      cond do
        env_a == 0 and not exact? ->
          {cr, cg, cb}

        below > 0 ->
          gl = env_a * (:math.exp(-below / 6) * 0.1)
          {cr + gl * 0.12, cg + gl * 0.62, cb + gl * 0.52}

        true ->
          gl = env_a * (:math.exp(below / 8) * 0.18)
          {cr + gl * 0.12, cg + gl * 0.62, cb + gl * 0.52}
      end

    # Airglow on the horizon.
    ag = glow * (0.1 + 0.16 * light_x)
    cg = cg + ag * 0.7
    cb = cb + ag * 0.75
    cr = cr + ag * 0.2

    case star do
      nil ->
        {cr, cg, cb}

      {st, speed, phase} ->
        tw = 0.7 + 0.3 * :math.sin(t * speed + phase)
        s = st * tw * clamp(1 - a * 1.6) * low
        {max(cr, s * 0.9), max(cg, s * 0.94), max(cb, s)}
    end
  end

  defp shade({:land, x, _bayer, m, cr, cg, cb, rec, rim, _lamp, _floor}, r, _y, _row, col, fr) do
    light_x = elem(col, 6)
    {t, flick, _, _, _} = fr
    l = light_x * rec
    cr = cr + l * 0.03
    cg = cg + l * 0.14
    cb = cb + l * 0.1

    {cr, cg, cb} =
      if rim > 0 do
        q = rim * if(m == @tree, do: 0.2 + 0.45 * light_x, else: 0.05 + 0.22 * light_x)
        {cr + q * 0.25, cg + q * 0.95, cb + q * 0.7}
      else
        {cr, cg, cb}
      end

    cond do
      m == @pane ->
        f = flick + 0.04 * :math.sin(t * 5.3 + x)
        {f, 0.76 * f, 0.38 * f}

      # Light through the crack of the door.
      m == @door and x == @door1 and r > @eave + 1 ->
        {0.55 * flick, 0.36 * flick, 0.14 * flick}

      true ->
        {cr, cg, cb}
    end
  end

  # Curtain A: a sharp lower hem, rays rising and fading to violet.
  # Where the curtain's envelope is 0 it adds exactly nothing.
  defp curtain_a(d, x, hc, env_a, bend, rays, cr, cg, cb, exact?)
       when d > -4 and d < 46 and (env_a > 0 or exact?) do
    lean = ray(rays, x + d * 0.22)

    prof =
      if d < 0,
        do: :math.exp(-d * d * 0.9),
        else: (1 - :math.exp(-(d + 0.4) * 1.1)) * :math.exp(-d / hc)

    # The rays, over a continuous bright band along the hem.
    band = if d < 0, do: :math.exp(-d * d), else: :math.exp(-d / 3)
    a = (prof * lean + 0.3 * band * (0.55 + 0.45 * min(1.4, lean))) * env_a * (1.15 + 0.35 * bend)
    up = clamp(d / (hc * 1.6))
    gk = 1 - smooth(0, 0.5, up)
    vk = smooth(0.4, 0.9, up)
    tk = 1 - gk - vk
    cr = cr + a * (0.18 * gk + 0.06 * tk + 0.42 * vk)
    cg = cg + a * (1.0 * gk + 0.78 * tk + 0.16 * vk)
    cb = cb + a * (0.48 * gk + 0.7 * tk + 0.75 * vk)
    # Pink at the very hem where it is brightest (none at all where a is at
    # most 0.3).
    if a > 0.3 or exact? do
      hem =
        :math.exp(-((d + 0.6) * (d + 0.6)) * 1.2) * smooth(0.3, 0.8, a) * 0.8 *
          (0.45 + 0.55 * min(1, lean))

      {cr + hem * 0.95, cg * (1 - 0.55 * min(1, hem * 1.6)), cb + hem * 0.4, a}
    else
      {cr, cg, cb, a}
    end
  end

  defp curtain_a(_d, _x, _hc, _env_a, _bend, _rays, cr, cg, cb, _exact?), do: {cr, cg, cb, 0}

  # Curtain B, further away, thinning out toward the top of the frame.
  defp curtain_b(db, x, env_b, high, rays, cr, cg, cb, a, exact?)
       when db > -3 and db < 30 and (env_b > 0 or exact?) do
    prof =
      if db < 0,
        do: :math.exp(-db * db),
        else: (1 - :math.exp(-(db + 0.4))) * :math.exp(-db / 9)

    b = prof * ray(rays, x + db * 0.18) * env_b * 0.85 * high
    up = clamp(db / 12)
    {cr + b * (0.1 + 0.4 * up), cg + b * (0.75 - 0.5 * up), cb + b * (0.7 + 0.2 * up), a + b}
  end

  defp curtain_b(_db, _x, _env_b, _high, _rays, cr, cg, cb, a, _exact?), do: {cr, cg, cb, a}

  # The water's ripples are value noise at (x * 0.04 + t * 0.05,
  # r * 0.55 - t * 0.35): a frame works out each column's lattice cell and
  # blend once, and each row hashes only the lattice points its cells fall
  # between. The same sums as noise/2, from far fewer hashes.
  defp wave_columns(tx, true),
    do: {List.to_tuple(for(x <- 0..(@w - 1), do: {x * 0.04 + tx, nil})), :exact}

  defp wave_columns(tx, false) do
    cols =
      for x <- 0..(@w - 1) do
        v = x * 0.04 + tx
        xi = floor(v)
        fx = v - xi
        {xi, fx * fx * (3 - 2 * fx)}
      end

    {base, _} = hd(cols)
    {last, _} = List.last(cols)
    {List.to_tuple(for {xi, u} <- cols, do: {xi - base, u}), {base, last - base}}
  end

  defp wave_row(:exact, y), do: {:at, y}

  defp wave_row({base, n}, y) do
    yi = floor(y)
    fy = y - yi

    {List.to_tuple(for i <- 0..(n + 1), do: hash(base + i, yi)),
     List.to_tuple(for i <- 0..(n + 1), do: hash(base + i, yi + 1)), fy * fy * (3 - 2 * fy)}
  end

  # noise/2 from its lattice, or noise/2 itself, the long way.
  defp wave({:at, y}, {x, nil}), do: noise(x, y)

  defp wave({lo, hi, v}, {i, u}) do
    a = elem(lo, i)
    b = elem(lo, i + 1)
    c = elem(hi, i)
    d = elem(hi, i + 1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  # Still water: the mirror image, stretched and broken by slow ripples.
  defp water_cells([], _row, _mirror, _fr, acc), do: acc

  defp water_cells([{x, bayer, road} | cells], row, mirror, fr, acc) do
    {r, _y, _dw, deep, fade, gap?, _ry, sway, r13} = row
    {row0, row1, row2, mats, waves, wave_row} = mirror
    {t, flick, _, _, _} = fr
    wave = wave(wave_row, elem(waves, x))
    sx = x + sway * :math.sin(r13 + t * 1.6 + wave * 4)
    ix = floor(sx)
    fx = sx - ix
    ix = max(0, min(@w - 2, ix))
    ms = elem(mats, ix)
    sky? = ms == @air
    kr = if(sky?, do: 0.55, else: 0.64) * (0.82 + 0.3 * wave) * deep
    kr = if sky? and gap? and wave < 0.45, do: kr * 0.12, else: kr

    # The cabin's own image is soft; the lamplight road below carries it.
    kr =
      cond do
        ms == @pane -> kr * 0.4
        ms in [@wall, @roof, @door] -> kr * 0.7
        true -> kr
      end

    gx = 1 - fx
    {r0a, g0a, b0a} = elem(row0, ix)
    {r0b, g0b, b0b} = elem(row0, ix + 1)
    {r1a, g1a, b1a} = elem(row1, ix)
    {r1b, g1b, b1b} = elem(row1, ix + 1)
    {r2a, g2a, b2a} = elem(row2, ix)
    {r2b, g2b, b2b} = elem(row2, ix + 1)

    cr =
      ((r0a * gx + r0b * fx) * 0.5 + (r1a * gx + r1b * fx) * 0.3 + (r2a * gx + r2b * fx) * 0.2) *
        kr

    cg =
      ((g0a * gx + g0b * fx) * 0.5 + (g1a * gx + g1b * fx) * 0.3 + (g2a * gx + g2b * fx) * 0.2) *
        kr

    cb =
      ((b0a * gx + b0b * fx) * 0.5 + (b1a * gx + b1b * fx) * 0.3 + (b2a * gx + b2b * fx) * 0.2) *
        kr

    {cr, cg, cb} =
      if ms != @wall and ms != @door,
        do: {cr + 0.02, cg + 0.035, cb + 0.065},
        else: {cr, cg, cb}

    # A pale line where the water meets the shore.
    {cr, cg, cb} =
      if r == @wl do
        e = 0.3 * (0.3 + 0.7 * smooth(0.25, 0.75, noise(x * 0.3, t * 0.4)))
        {cr + e * 0.6, cg + e * 0.85, cb + e}
      else
        {cr, cg, cb}
      end

    # The lamplight laid on the water as a broken golden road.
    {cr, cg, cb} =
      case road do
        nil ->
          {cr, cg, cb}

        {e1, e2} ->
          rip = smooth(0.3, 0.65, noise(x * 0.5 - t * 0.2, r * 1.4 - t * 1.5))
          [{_, s1}, {_, s2}] = @lamps
          g = e1 * rip * s1 * 1.6 * flick
          {cr, cg, cb} = {cr + g, cg + g * 0.68, cb + g * 0.28}
          g = e2 * rip * s2 * 1.6 * flick
          {cr + g, cg + g * 0.68, cb + g * 0.28}
      end

    floor = if sky?, do: 0.07 * deep, else: 0.03
    water_cells(cells, row, mirror, fr, dot(cr, cg, cb, floor, fade, bayer, acc))
  end

  # Dot size from brightness, dithered. Then the colour makes up what the dot
  # size could not: a small dot is drawn brighter and a large one dimmer, so
  # a gradient stays smooth across the dither's steps.
  #
  # Math.pow is slow, so the level is first found with power/2, within
  # 1e-13 of pow(peak, 0.85).
  # Every decision the level feeds (the dot's rounding, the colour's step in
  # the cache, a cache miss) is then checked: when one sits within 1e-8 of
  # its threshold, or the colour is not cached yet, the cell is worked out
  # again with :math.pow, so the result is always upstream's.
  defp dot(cr, cg, cb, fl, fade, bayer, {_, _, _, _, :exact} = acc),
    do: exact_dot(cr, cg, cb, fl, fade, bayer, cr |> max(cg) |> max(cb) |> max(1.0e-4), acc)

  defp dot(cr, cg, cb, fl, fade, bayer, {text, colors, lut, color?, power} = acc) do
    peak = cr |> max(cg) |> max(cb) |> max(1.0e-4)
    level = clamp(fl + (1 - fl) * power(peak, power) * 0.95) * fade
    v = level * 3 + bayer
    whole = floor(v)
    f = v - whole

    if abs(f - 0.5) < @margin do
      exact_dot(cr, cg, cb, fl, fade, bayer, peak, acc)
    else
      # Math.round, away from the half.
      step = if f < 0.5, do: whole, else: whole + 1
      step = max(0, min(3, step))
      text = <<text::binary, elem(@dots, step)::binary>>

      if color? do
        want = if step != 0, do: min(1, (level + 0.06) / elem(@cover, step)), else: 0
        s = (0.3 + 0.7 * want) / peak
        {_palette, answers} = lut
        key = key(clamp(cr * s), clamp(cg * s), clamp(cb * s))

        # A key sits in the cache only once its colour has been worked out
        # exactly; nil, a channel too near a step, is never a key.
        case answers do
          %{^key => index} -> {text, <<colors::binary, index>>, lut, true, power}
          _ -> exact_color(cr, cg, cb, fl, fade, bayer, peak, {text, colors, lut, true, power})
        end
      else
        {text, colors, lut, false, power}
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

  # A colour's key in the cache, as `Palette.nearest/4` makes it, or nil
  # when a channel sits within the margin of a step of the cache.
  defp key(r, g, b) do
    with kr when kr != nil <- cube(r),
         kg when kg != nil <- cube(g),
         kb when kb != nil <- cube(b),
         do: bsl(kr, 10) ||| bsl(kg, 5) ||| kb
  end

  defp cube(c) do
    w = c * 31.99
    k = trunc(w)
    f = w - k
    if (f < @margin and k >= 1) or f > 1 - @margin, do: nil, else: min(31, k)
  end

  defp exact_level(fl, fade, peak),
    do: clamp(fl + (1 - fl) * :math.pow(peak, @gamma) * 0.95) * fade

  defp exact_dot(cr, cg, cb, fl, fade, bayer, peak, {text, colors, lut, color?, power}) do
    level = exact_level(fl, fade, peak)
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
  defp exact_color(cr, cg, cb, fl, fade, bayer, peak, {text, colors, lut, true, power}) do
    level = exact_level(fl, fade, peak)
    step = max(0, min(3, round_js(level * 3 + bayer)))
    {r, g, b} = tint(cr, cg, cb, level, step, peak)
    {index, lut} = Palette.nearest(lut, r, g, b)
    {text, <<colors::binary, index>>, lut, true, power}
  end

  # Math.round: halves toward +infinity.
  defp round_js(x) do
    c = ceil(x)
    if c - 0.5 > x, do: c - 1, else: c
  end
end
