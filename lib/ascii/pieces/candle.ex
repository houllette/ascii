defmodule Ascii.Pieces.Candle do
  @moduledoc """
  A flickering candle burning down in its holder, then renewed.

  A candle in a brass candlestick. The flame flickers and sways, its glow
  lighting the wax and the metal, and the candle burns slowly down; when it
  gutters out the stub is lifted away and a fresh one is set in and lit.

  The candlestick is turned on a lathe once, in `init/1`, onto a grid two
  columns and four rows to a cell; each frame lights what it holds, and the
  wax, which moves, is traced afresh in the few columns it can cover.

  Ported from `src/pieces/candle.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}

  @meta %Ascii.Meta{
    name: "candle",
    category: :objects,
    note: "a flickering candle burning down in its holder, then renewed",
    cols: 40,
    rows: 30,
    fps: 15
  }

  @cols 40
  @rows 30
  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # How steeply we look down on it.
  @sn 0.4
  @cs :math.sqrt(1 - 0.4 * 0.4)
  # The candle's radius, in rows.
  @r 2.1
  @rr 2.1 * 2.1
  # The candle's height new and spent, above the socket; where it stands in the holder.
  @full 9.6
  @stub 1.2
  @socket 11
  # The cycle, in seconds: lit, burning down, guttering, smoke, the stub out,
  # a new one in, a breath.
  @steps {1.2, 26, 1.4, 2.4, 1.6, 2.2, 0.5}
  @cycle Enum.reduce([1.2, 26, 1.4, 2.4, 1.6, 2.2, 0.5], 0, &(&2 + &1))
  # A little way down, with a few drips.
  @t0 4.6
  # The candlestick, foot to socket, as {radius, height} round its axis.
  @stick [
    {4.4, 0},
    {4.6, 0.3},
    {4.4, 0.65},
    {3.6, 0.95},
    {2.4, 1.25},
    {1.35, 1.6},
    {0.82, 2.1},
    {0.66, 3},
    {0.7, 4.1},
    {1.05, 4.45},
    {1.5, 4.9},
    {1.6, 5.4},
    {1.45, 5.9},
    {1.0, 6.2},
    {0.66, 6.5},
    {0.6, 7.6},
    {0.6, 8.7},
    {1.0, 9.1},
    {2.4, 9.55},
    {3.8, 9.75},
    {4.3, 10},
    {4.35, 10.3},
    {4.1, 10.35},
    {3.5, 10.1},
    {2.7, 10.05},
    {2.45, 10.1},
    {2.45, 11.15},
    {2.25, 11.3}
  ]
  # Drips: angle round the front, longest run in rows, seconds into the burn
  # they start, fatness.
  @drips [
    {-1.3, 4.5, 0.5, 0.42},
    {0.45, 3, 2, 0.34},
    {1.32, 5, 3.5, 0.42},
    {-0.5, 2.2, 6, 0.32},
    {0.95, 3.6, 10, 0.36},
    {-1.05, 4, 14, 0.38},
    {0.15, 2.6, 18, 0.3},
    {1.25, 3, 21, 0.38}
  ]

  # Sub-cells: two across and four down to a character.
  @sx 2
  @sy 4
  @w 40 * 2
  @hh 30 * 4
  @cx 40 / 2
  # The screen row of the foot's centre.
  @base 30 - 2.4
  # The room's light, from the front left.
  @key {-0.45, 0.35, 0.82}

  @impl true
  def meta, do: @meta

  @compile {:inline, clamp: 1, ease: 1, row_of: 2, hypot3: 3}
  defp clamp(v), do: min(1, max(0, v))

  defp ease(u), do: clamp(u) * clamp(u) * (3 - 2 * clamp(u))

  defp row_of(y, z), do: @base - (y * @cs - z * @sn)

  # Math.hypot of three, as V8 sums it (see JSMath.hypot_list/1), inlined.
  defp hypot3(a, b, c) do
    a = abs(a)
    b = abs(b)
    c = abs(c)
    m = max(max(a, b), c)

    if m == 0 do
      0.0
    else
      x = a / m
      y = b / m
      z = c / m
      s1 = x * x
      sum = s1 + y * y
      comp = sum - s1 - y * y
      :math.sqrt(sum + (z * z - comp)) * m
    end
  end

  defp hash(n) do
    h = Int32.imul(Int32.bxor(n, 0x5BD1E995), 0x27D4EB2D)
    h = Int32.imul(Int32.bxor(h, Int32.ushr(h, 15)), 0x85EBCA6B)
    Int32.ushr(Int32.bxor(h, Int32.ushr(h, 13)), 0) / 4_294_967_296
  end

  defp noise(x) do
    i = JSMath.floor(x)
    u = x - i
    e = u * u * (3 - 2 * u)
    hash(i) + (hash(i + 1) - hash(i)) * e
  end

  @impl true
  def init(_options) do
    {k0, k1, k2} = @key
    km = JSMath.hypot(k0, k1 + @sn, k2 + @cs)
    kh = {k0 / km, (k1 + @sn) / km, (k2 + @cs) / km}

    geo = Map.new(lathe(), fn {k, {d, g}} -> {k, metal_record(d, g, kh)} end)

    cells =
      for r <- 0..(@rows - 1),
          c <- 0..(@cols - 1),
          subs = cell_subs(r, c, geo),
          Enum.any?(subs, &(&1 != {nil, nil})),
          do: {r * @cols + c, subs}

    drips =
      for {da, dl, start, fat} <- @drips do
        {(@r + 0.05) * :math.sin(da), (@r + 0.05) * :math.cos(da),
         @socket + @full - (@full - @stub) * (start / elem(@steps, 1)), dl, start, fat}
      end

    %{cells: cells, drips: drips}
  end

  # The candlestick, turned on a lathe: the nearest surface behind each look,
  # kept with its position and normal so the flame can light it each frame.
  defp lathe do
    @stick
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(%{}, fn [{r1, y1}, {r2, y2}], acc ->
      len = JSMath.hypot(r2 - r1, y2 - y1)
      nr = (y2 - y1) / len
      ny = -(r2 - r1) / len
      rings(acc, 0, {r1, y1, r2, y2, len, nr, ny})
    end)
  end

  defp rings(acc, f, {r1, y1, r2, y2, len, nr, ny} = seg) when f <= 1 do
    r = r1 + (r2 - r1) * f
    y = y1 + (y2 - y1) * f
    acc = around(acc, 0, r, y, nr, ny)
    rings(acc, f + 0.03 / len, seg)
  end

  defp rings(acc, _f, _seg), do: acc

  @two_pi 2 * :math.pi()

  defp around(acc, a, r, y, nr, ny) when a < @two_pi do
    ca = :math.cos(a)
    sa = :math.sin(a)
    x = r * ca
    z = r * sa
    px = floor((@cx + 2 * x) * @sx)
    py = floor(row_of(y, z) * @sy)

    acc =
      if px < 0 or px >= @w or py < 0 or py >= @hh,
        do: acc,
        else: plot(acc, py * @w + px, z * @cs + y * @sn, {x, y, z, nr * ca, ny, nr * sa})

    around(acc, a + 0.08 / max(r, 0.5), r, y, nr, ny)
  end

  defp around(acc, _a, _r, _y, _nr, _ny), do: acc

  defp plot(acc, k, d, g) do
    case acc do
      %{^k => {near, _}} when d <= near ->
        acc

      _ ->
        {x, y, z, nx, ny, nz} = g

        Map.put(
          acc,
          k,
          {JSMath.fround(d),
           {JSMath.fround(x), JSMath.fround(y), JSMath.fround(z), JSMath.fround(nx),
            JSMath.fround(ny), JSMath.fround(nz)}}
        )
    end
  end

  # What the room's light gives the brass doesn't move: keep it with the point.
  defp metal_record(d, {gx, gy, gz, nx, ny, nz}, {h0, h1, h2}) do
    {k0, k1, k2} = @key
    key = max(0, nx * k0 + ny * k1 + nz * k2)
    ks = max(0, nx * h0 + ny * h1 + nz * h2)
    kspec = if ks > 0, do: :math.pow(ks, 6), else: 0
    {gx, gy, gz, nx, ny, nz, d, 0.16 * key, 0.85 * kspec}
  end

  # A cell's eight sub-cells, row by row, each as its brass (or nil) and its
  # place in the columns the wax can cover (or nil).
  defp cell_subs(r, c, geo) do
    for j <- 0..(@sy - 1), i <- 0..(@sx - 1) do
      k = (r * @sy + j) * @w + c * @sx + i
      {Map.get(geo, k), strip_record(k)}
    end
  end

  defp strip_record(k) do
    sx = (rem(k, @w) + 0.5) / @sx
    sy = (div(k, @w) + 0.5) / @sy
    x = (sx - @cx) / 2

    if abs(x) < @r + 0.4 do
      {k0, _, k2} = @key
      z = :math.sqrt(max(0, @rr - x * x))
      yb = (@base - sy + z * @sn) / @cs
      nx = x / @r
      nz = z / @r
      key = max(0, nx * k0 + nz * k2)

      {x, x * x, @base - sy, sy - @base, yb, z * @cs + yb * @sn, abs(x) < @r, 0.7 * key,
       0.5 + 0.5 * nz}
    end
  end

  @impl true
  def frame(state, time, env) do
    # Where in the cycle we are: how far burnt, the flame's strength, the
    # candle's lift and fade.
    k0 = JSMath.mod(JSMath.mod(@t0 + time, @cycle) + @cycle, @cycle)
    {k0, step} = step(k0, 0)
    {tb, flame, flare, smoke, lift, fade} = stage(step, k0, k0 / elem(@steps, step), time)
    h = @full - (@full - @stub) * (tb / elem(@steps, 1))
    y_top = @socket + h + lift
    ys = @socket - 0.6 + lift

    # The flame: its height, lean and brightness wander, with a gust now and then.
    gust = clamp((noise(time * 0.45 + 3) - 0.62) * 3)

    hf =
      flame * (4.3 + 1.1 * noise(time * 2.3) - 1.3 * gust * noise(time * 9 + 1)) *
        (1 + 0.7 * flare)

    sway = 0.4 * (noise(time * 1.2 + 7) - 0.5) + 0.25 * gust * :math.sin(time * 11)
    bright = min(1.3, flame * (0.75 + 0.25 * noise(time * 3.1 + 11)) + 0.4 * flare)
    # Its heart, where the light comes from.
    fx = sway * 0.3
    fy = y_top + 0.4 + hf * 0.32

    p = %{
      fx: fx,
      fy: fy,
      bright: bright,
      bm: 0.55 + 0.45 * min(1, bright),
      fade: fade,
      wax?: fade > 0.02,
      y_top: y_top,
      ys: ys,
      ytc: y_top * @cs,
      yts: y_top * @sn,
      drips: drips(state.drips, tb, lift, y_top, ys)
    }

    {out, solid} = shade(state.cells, p, env.paper)
    fc = @cx + 2 * fx
    out = if bright > 0.05, do: halo(out, solid, fc, row_of(fy, 0), bright), else: out
    out = if hf > 0.2, do: flame(out, fc, y_top + 0.1, hf, flare, fx, sway), else: out

    # The wick, standing bare once the flame is out.
    wr = floor(row_of(y_top + 0.35, 0))

    out =
      if hf <= 0.2 and fade > 0.5 and wr >= 0 and wr < @rows,
        do: Map.put(out, wr * @cols + floor(@cx), "'"),
        else: out

    out = if smoke >= 0, do: smoke(out, smoke, row_of(y_top - lift + 0.4, 0)), else: out

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp step(k0, step) when step < tuple_size(@steps) - 1 and k0 > elem(@steps, step),
    do: step(k0 - elem(@steps, step), step + 1)

  defp step(k0, step), do: {k0, step}

  # {burnt, flame, flare, smoke, lift, fade} for each part of the cycle.
  defp stage(0, _k0, u, _time),
    do: {0, ease(u * 4), :math.sin(:math.pi() * clamp(u * 1.6)) * (1 - u), -1, 0, 1}

  defp stage(1, k0, _u, _time), do: {k0, 1, 0, -1, 0, 1}

  defp stage(2, _k0, u, time),
    do: {elem(@steps, 1), (1 - u) * (0.6 + 0.4 * noise(time * 14)), 0, -1, 0, 1}

  defp stage(3, k0, _u, _time), do: {elem(@steps, 1), 0, 0, k0, 0, 1}

  defp stage(4, k0, u, _time),
    do: {elem(@steps, 1), 0, 0, elem(@steps, 3) + k0, 4.5 * ease(u), 1 - ease(u * 1.15)}

  defp stage(5, _k0, u, _time),
    do: {0, 0, 0, -1, 13 * (1 - :math.sin(:math.pi() / 2 * u)), 1}

  defp stage(_step, _k0, _u, _time), do: {0, 0, 0, -1, 0, 1}

  # Each drip under way: its foot, the top of its run, and where it sits round
  # the candle.
  defp drips(drips, tb, lift, y_top, ys) do
    for {cx, cz, top, dl, start, fat} <- drips,
        y0 = top + lift - 0.3,
        run = min(dl, (tb - start) * 0.8),
        not (run <= 0 or y0 - run > y_top - 0.2) do
      y1 = max(ys, y0 - run)
      {cx, cz, y1, min(y0, y_top - 0.15), fat, fat * fat, cx + fat * 0.9, cx + fat + 0.32}
    end
  end

  # Down to cells: each sub-cell's light, averaged over those that hold
  # something. Returns the drawn cells and those holding anything at all.
  defp shade(cells, p, paper) do
    Enum.reduce(cells, {%{}, %{}}, fn {idx, subs}, {out, solid} ->
      {n, s} =
        Enum.reduce(subs, {0, 0}, fn sub, {n, s} ->
          case sub(sub, p) do
            {_v, 0} -> {n, s}
            {v, _} -> {n + 1, s + JSMath.fround(v)}
          end
        end)

      solid = if n > 0, do: Map.put(solid, idx, true), else: solid

      if n >= 3 do
        i = max(1, min(9, JSMath.round(clamp(s / n) * 9)))
        {Map.put(out, idx, elem(@ramp, if(paper, do: 10 - i, else: i))), solid}
      else
        {out, solid}
      end
    end)
  end

  defp sub({nil, nil}, _p), do: {-1, 0}
  defp sub({nil, strip}, p), do: wax(strip, -1, -1.0e9, 0, p)
  defp sub({metal, nil}, p), do: {brass(metal, p), 1}
  defp sub({metal, strip}, p), do: wax(strip, brass(metal, p), elem(metal, 6), 1, p)

  # Brass: the flame's light and its glint, and the room's from the left,
  # glinting too.
  defp brass({gx, gy, gz, nx, ny, nz, _d, k16, k85}, %{fx: fx, fy: fy, bright: bright}) do
    lx = fx - gx
    ly = fy - gy
    lz = -gz
    ld = hypot3(lx, ly, lz)
    diff = max(0, (nx * lx + ny * ly + nz * lz) / ld)
    hx = lx / ld
    hy = ly / ld + @sn
    hz = lz / ld + @cs
    hm = hypot3(hx, hy, hz)
    sp = (nx * hx + ny * hy + nz * hz) / hm
    spec = if sp > 0, do: :math.pow(sp, 6), else: 0
    q = ld / 14
    0.08 + (0.4 * diff + 0.7 * spec) * bright / (1 + q * q) + k16 + k85
  end

  # The wax: its top, its body and the drips over them, nearest first.
  defp wax(_strip, v, _d, kd, %{wax?: false}), do: {v, kd}

  defp wax(strip, v, d, kd, p) do
    {v, d, kd} = top_or_body(strip, v, d, kd, p)
    {v, _d, kd} = Enum.reduce(p.drips, {v, d, kd}, &drip(&1, strip, &2, p))
    {v, kd}
  end

  defp top_or_body(strip, v, d, kd, p) do
    {x, xx, _bms, syb, yb, front, body?, k7, nzf} = strip
    zt = (syb + p.ytc) / @sn

    cond do
      xx + zt * zt < @rr and zt * @cs + p.yts > d ->
        # The top: a pool of melted wax lit by the flame, its rim brightest.
        rim = JSMath.hypot(x, zt) / @r
        bright = p.bright

        {(0.3 + 0.35 * bright + 0.25 * bright * :math.pow(rim, 4)) * p.fade, zt * @cs + p.yts, 2}

      body? and yb < p.y_top and yb > p.ys and front > d ->
        v = (0.05 + k7 * p.bm + glow(p.y_top - yb, p.bright) * nzf) * p.fade
        # A drip throws a thin shadow on the wax to its right.
        v =
          Enum.reduce(p.drips, v, fn {_cx, _cz, y1, y0, _fat, _ff, x09, x32}, v ->
            if x > x09 and x < x32 and yb < y0 and yb > y1 - 0.2, do: v * 0.55, else: v
          end)

        {v, front, 2}

      true ->
        {v, d, kd}
    end
  end

  defp glow(below, bright),
    do: (0.55 * :math.exp(-below / 2.2) + 0.25 * :math.exp(-below / 0.6)) * bright

  # The drips, each a rounded run down the side, standing out from it.
  defp drip({cx, cz, y1, y0, fat, ff, _x09, _x32}, strip, {_v, d, _kd} = acc, p) do
    {x, _xx, bms, _syb, _yb, _front, _body?, _k7, _nzf} = strip
    dx = x - cx

    if abs(dx) >= fat do
      acc
    else
      dz = :math.sqrt(ff - dx * dx)
      zz = cz + dz
      yy = (bms + zz * @sn) / @cs
      tip = y1 + fat - yy

      cond do
        # The round bulb at its foot.
        yy < y1 + fat and dx * dx + tip * tip > ff ->
          acc

        yy > y0 or zz * @cs + yy * @sn <= d - 0.02 ->
          acc

        true ->
          {(wax_at(dx / fat, dz / fat, p.y_top - yy, p) + 0.1) * p.fade, zz * @cs + yy * @sn, 2}
      end
    end
  end

  # The wax: a cylinder lit by the room, glowing through near the top.
  defp wax_at(nx, nz, below, p) do
    {k0, _, k2} = @key
    key = max(0, nx * k0 + nz * k2)
    0.05 + 0.7 * key * p.bm + glow(below, p.bright) * (0.5 + 0.5 * nz)
  end

  # A soft halo, a ring of fine dots inside a ring of fainter ones, kept clear
  # of the solid.
  defp halo(out, solid, fc, fr, bright) do
    reach = 2.4 + 1.4 * min(1, bright)

    for r <- 0..(@rows - 1), c <- 0..(@cols - 1), reduce: out do
      out ->
        g = JSMath.hypot((c + 0.5 - fc) / 2 / 1.05, (r + 0.5 - fr) / 1.35) / reach
        idx = r * @cols + c

        if g > 1 or (g > 0.66 and g < 0.84) or Map.has_key?(out, idx) or near?(solid, r, c),
          do: out,
          else: Map.put(out, idx, if(g < 0.66, do: "·", else: "."))
    end
  end

  # Upstream reads the flat array, so a neighbour off one side of a row is the
  # end of the next or the last.
  defp near?(solid, r, c) do
    Enum.any?([-1, 0, 1], fn j ->
      Enum.any?([-1, 0, 1], fn i -> Map.has_key?(solid, (r + j) * @cols + c + i) end)
    end)
  end

  # A teardrop on the wick, swaying at the tip, with a dim root and the wick
  # dark in its heart.
  defp flame(out, fc, y0, hf, flare, fx, sway) do
    r0 = floor(row_of(y0 + hf + 0.5, 0))
    r1 = ceil(row_of(y0 - 0.5, 0))
    c0 = floor(fc - 5)
    width = 1.2 + 0.25 * flare

    for r <- r0..r1//1,
        c <- Stream.iterate(c0, &(&1 + 1)) |> Enum.take_while(&(&1 <= fc + 5)),
        r >= 0 and r < @rows and c >= 0 and c < @cols,
        reduce: out do
      out ->
        s =
          for j <- 0..(@sy - 1), i <- 0..(@sx - 1), reduce: 0 do
            s -> s + tongue(r, c, j, i, {y0, hf, width, fx, sway})
          end

        v = s / (@sx * @sy)

        if v > 0.06,
          do: Map.put(out, r * @cols + c, elem(@ramp, max(1, min(9, JSMath.round(v * 9 + 0.3))))),
          else: out
    end
  end

  defp tongue(r, c, j, i, {y0, hf, width, fx, sway}) do
    y = (@base - (r + (j + 0.5) / @sy)) / @cs - y0 + 0.35
    uu = y / (hf + 0.35)

    if uu <= 0 or uu >= 1 do
      0
    else
      w = width * (:math.sqrt(uu) * :math.pow(1 - uu, 1.2)) / 0.36
      q = ((c + (i + 0.5) / @sx - @cx) / 2 - fx - sway * uu * uu) / w

      cond do
        abs(q) >= 1 -> 0
        uu < 0.18 -> (1 - q * q) * 0.4
        uu < 0.32 and abs(q) < 0.35 -> (1 - q * q) * 0.55
        true -> (1 - q * q) * (0.8 + 0.4 * min(1, uu * 2.5))
      end
    end
  end

  # Once it is out, a thread of smoke from the wick, thinning as it climbs.
  defp smoke(out, smoke, wick) do
    Enum.reduce(0..9, out, fn n, out ->
      s = 1.5 + n
      r = floor(wick - s)
      age = smoke - s / 4

      if r < 0 or age < 0 or age > 2 do
        out
      else
        x = @cx + 0.4 + 0.5 * (s / 3) * :math.sin(0.9 * s - smoke * 3)
        lean = :math.cos(0.9 * s - smoke * 3)

        ch =
          cond do
            age > 1.4 -> "."
            lean > 0.5 -> ")"
            lean < -0.5 -> "("
            true -> "|"
          end

        Map.put(out, r * @cols + floor(x), ch)
      end
    end)
  end
end
