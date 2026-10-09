defmodule Ascii.Pieces.Glxgears do
  @moduledoc """
  Three meshing gears turning, after glxgears.

  The three gears of gears.c, with their sizes, places and view, in block
  shades. Each gear's face keeps one shade, as each has one colour there; the
  walls of the teeth and the bores are bright where they catch the light.

  Ported from `src/pieces/glxgears.ts` in bas3line/ascii (MIT).

  ## How the depth buffer is reproduced

  Upstream plots some 67,000 points a frame into a `Float32Array` depth
  buffer of two samples a cell each way. A sample ends up holding the point
  whose depth rounds (to single precision) to the largest value, `m`; when
  several round to `m`, the last one plotted that lies above `m` wins, or
  else the first one plotted. That is independent of the order of plotting,
  so this port keeps, per sample, the largest depth seen (as an integer,
  quantised) and remembers every point that came within a float32 rounding
  step of the largest; only samples where such points belong to different
  shades are settled exactly, by upstream's rule.

  That lets the 27,000 points of the gears' faces be placed by rotating
  their resting positions with one sine and cosine of the turn, instead of
  `Math.sin` and `Math.cos` of each point's angle. A point whose position
  lands within a hair of a sample's edge, or whose depth decides something,
  is computed exactly as upstream does, so frames stay bit for bit.
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  import Bitwise

  @meta %Ascii.Meta{
    name: "glxgears",
    category: :shapes,
    note: "three meshing gears turning, after glxgears",
    cols: 56,
    rows: 31,
    fps: 24
  }

  @cols 56
  @rows 31
  # Two samples a cell each way.
  @w @cols * 2
  @h @rows * 2
  @tau :math.pi() * 2
  @rad :math.pi() / 180
  # Columns per unit, the spacing of sampled points in units, and degrees a
  # second for the big gear.
  @scale 4.2
  @ds 0.05
  @speed 17
  @shade {" ", "░", "▒", "▓", "█"}
  # Tooth depth; gears.c has 0.7.
  @depth 0.8

  # Depths (always within ±8 here) are kept as integers: offset, then
  # quantised to 2^-22. A float32 rounding step at that size is two quanta;
  # points within @margin quanta of a sample's largest are kept for an exact
  # look.
  @offset 32.0
  @quanta 4_194_304.0
  @margin 18
  @margin_depth @margin / @quanta
  # A key: quantised depth, then the class (gear * 5 + shade), then the
  # point's place in upstream's plotting order.
  @class_shift 17
  @depth_shift 21

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    # glRotatef(view_rotx = 20) then glRotatef(view_roty = 30); light at (5, 5, 10).
    view =
      {:math.cos(30 * @rad), :math.sin(30 * @rad), :math.cos(20 * @rad), :math.sin(20 * @rad)}

    m = JSMath.hypot(5, 5, 10)
    light = {5 / m, 5 / m, 10 / m}
    specs = specs()
    {left, high} = frame_origin(specs, view)
    ctx = %{view: view, light: light, left: left, high: high}

    {gears, _} =
      specs
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {spec, i}, next -> gear(spec, i, next, ctx) end)

    Map.put(ctx, :gears, gears)
  end

  # gear(inner, outer, width, teeth), its place, its turn as k * a + off, and
  # its face's shade. Twelve and six teeth for twenty and ten, so each tooth is
  # wide enough to read.
  defp specs do
    raw = [
      %{r0: 1.0, r: 4.0, w: 1.0, n: 12, x: -3.0, y: -2.0, k: 1, off: 0, face: 3},
      %{r0: 0.5, r: 2.0, w: 2.0, n: 6, x: 3.1, y: -2.0, k: -2, off: nil, face: 2},
      %{r0: 1.3, r: 2.0, w: 0.5, n: 6, x: -3.1, y: 4.2, k: -2, off: nil, face: 2}
    ]

    big = hd(raw)

    # Offsets that set each small gear's gap on a tooth of the big one.
    Enum.map(raw, fn g ->
      g = Map.merge(g, %{r1: g.r - @depth / 2, r2: g.r + @depth / 2})

      if g.k == 1 do
        g
      else
        dir = :math.atan2(g.y - big.y, g.x - big.x)
        off = (dir + :math.pi() - (0.875 - dir * big.n / @tau + 0.375) * @tau / g.n) / @rad
        %{g | off: off}
      end
    end)
  end

  @compile {:inline, across: 3, up: 4, depth: 4, quantise: 1, key: 3}
  defp across(x, z, {cy, sy, _, _}), do: x * cy + z * sy
  defp up(x, y, z, {cy, sy, cx, sx}), do: y * cx + (x * sy - z * cy) * sx
  defp depth(x, y, z, {cy, sy, cx, sx}), do: y * sx + (z * cy - x * sy) * cx
  defp quantise(d), do: trunc((d + @offset) * @quanta)

  defp key(d, class, idx),
    do: bor(bor(bsl(quantise(d), @depth_shift), bsl(class, @class_shift)), idx)

  # Centre the gears' outer circles in the frame.
  defp frame_origin(specs, view) do
    {left, right, high, low} =
      Enum.reduce(specs, {nil, nil, nil, nil}, fn g, acc ->
        0
        |> steps(0.02, &(&1 < @tau))
        |> Enum.reduce(acc, fn th, acc ->
          Enum.reduce([-g.w / 2, g.w / 2], acc, fn z, {l, r, hi, lo} ->
            x = g.x + g.r2 * :math.cos(th)
            y = g.y + g.r2 * :math.sin(th)
            a = across(x, z, view)
            u = up(x, y, z, view)
            {min_of(l, a), max_of(r, a), max_of(hi, u), min_of(lo, u)}
          end)
        end)
      end)

    {left - (@cols / @scale - (right - left)) / 2, high + (2 * @rows / @scale - (high - low)) / 2}
  end

  defp min_of(nil, b), do: b
  defp min_of(a, b), do: min(a, b)
  defp max_of(nil, b), do: b
  defp max_of(a, b), do: max(a, b)

  # The values a JS loop `for (v = from; test(v); v += step)` takes.
  defp steps(from, step, test), do: from |> Stream.iterate(&(&1 + step)) |> Enum.take_while(test)

  # The tooth outline as radius by angle: up a flank, across, down, the root.
  defp radius(g, th) do
    u = th * g.n / @tau - floor(th * g.n / @tau)

    rise =
      cond do
        u < 0.25 -> u * 4
        u < 0.5 -> 1
        u < 0.75 -> (0.75 - u) * 4
        true -> 0
      end

    g.r1 + (g.r2 - g.r1) * rise
  end

  # Everything about a gear that does not turn, with the place in upstream's
  # plotting order of its first face point, wall point and bore point.
  defp gear(g, i, next, %{view: {cy, sy, _, _} = view} = ctx) do
    h = g.w / 2

    # The front face, ring by ring. The back face never turns to the eye.
    face =
      for r <- steps(g.r0, @ds, &(&1 < g.r2)),
          th <- steps(0, @ds / r, &(&1 < @tau)),
          r <= radius(g, th),
          do: {r * :math.cos(th), r * :math.sin(th), r, th}

    face_lo = next
    wall_lo = face_lo + length(face)

    face =
      face
      |> Enum.with_index(face_lo)
      |> Enum.map(fn {{u, v, r, th}, idx} -> {u, v, r, th, idx} end)

    zs = steps(-h, @ds, &(&1 <= h))
    nz = length(zs)
    walls = wall(g, 0, [])
    bore_lo = wall_lo + length(walls) * nz
    {bore, bore_d} = bore(g, i, zs, bore_lo, ctx)
    bore_hi = bore_lo + length(steps(0, @ds / g.r0, &(&1 < @tau))) * nz

    gear = %{
      i: i,
      x: g.x,
      y: g.y,
      h: h,
      k: g.k,
      off: g.off,
      face_class: i * 5 + g.face,
      face: face,
      face_at: List.to_tuple(face),
      face_lo: face_lo,
      walls:
        walls
        |> Enum.with_index()
        |> Enum.map(fn {{th, r, dr, l}, j} -> {th, r, dr, l, wall_lo + j * nz} end),
      wall_at: List.to_tuple(walls),
      wall_lo: wall_lo,
      zs: zs |> Enum.with_index() |> Enum.map(fn {z, j} -> {z * sy, z * cy, j} end),
      z_at: List.to_tuple(zs),
      nz: nz,
      bore: bore,
      bore_d: bore_d,
      bore_lo: bore_lo,
      view: view,
      left: ctx.left,
      high: ctx.high
    }

    {gear, bore_hi}
  end

  # The outer wall, walked by arc length so the flanks are as dense as the tips.
  defp wall(_g, th, acc) when th >= @tau, do: Enum.reverse(acc)

  defp wall(g, th, acc) do
    r = radius(g, th)
    dr = (radius(g, th + 1.0e-4) - radius(g, th - 1.0e-4)) / 2.0e-4
    l = JSMath.hypot(r, dr)
    wall(g, th + @ds / l, [{th, r, dr, l} | acc])
  end

  # The bore, facing in, never turns on screen: every point is known here.
  # Per sample only two points can matter, the first to reach the sample's
  # rounded depth and the last to pass it.
  defp bore(g, i, zs, bore_lo, %{view: view, light: light, left: left, high: high}) do
    points =
      for {th, j} <- Enum.with_index(steps(0, @ds / g.r0, &(&1 < @tau))),
          c = :math.cos(th),
          s = :math.sin(th),
          {z, zi} <- Enum.with_index(zs),
          x = g.x + g.r0 * c,
          y = g.y + g.r0 * s,
          k = sample(x, y, z, view, left, high),
          k != nil,
          tone = wall_tone(-c, -s, view, light),
          tone != nil,
          do: {k, depth(x, y, z, view), i * 5 + tone, bore_lo + j * length(zs) + zi}

    kept =
      points
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.flat_map(fn {_k, ps} -> deciders(ps) end)
      |> Enum.sort_by(&elem(&1, 3))

    {Enum.map(kept, fn {k, d, class, idx} -> {k, key(d, class, idx)} end),
     Map.new(kept, fn {_, d, _, idx} -> {idx, d} end)}
  end

  # Of points in one sample, in plotting order, the ones upstream's rule can
  # pick: the first to round to the largest depth, the last above it.
  defp deciders(ps) do
    m = ps |> Enum.map(&JSMath.fround(elem(&1, 1))) |> Enum.max()
    j = Enum.filter(ps, &(JSMath.fround(elem(&1, 1)) == m))
    Enum.uniq([hd(j) | Enum.take(Enum.filter(j, &(elem(&1, 1) > m)), -1)])
  end

  defp sample(x, y, z, view, left, high) do
    col = floor((across(x, z, view) - left) * @scale * 2)
    row = floor((high - up(x, y, z, view)) * @scale)
    if col < 0 or col >= @w or row < 0 or row >= @h, do: nil, else: row * @w + col
  end

  # A wall faces away (nil), or is full where it faces the light, and faint
  # where it does not.
  defp wall_tone(nx, ny, {cy, sy, cx, sx}, {l0, l1, l2}) do
    vx = nx * cy
    vy = ny * cx + nx * sy * sx
    vz = ny * sx - nx * sy * cx

    cond do
      vz < 0 -> nil
      vx * l0 + vy * l1 + vz * l2 > 0.42 -> 4
      true -> 1
    end
  end

  @impl true
  def frame(state, t, env) do
    a = @speed * t
    best = :atomics.new(@w * @h, signed: true)

    {near, spins} =
      Enum.reduce(state.gears, {[], []}, fn g, {near, spins} ->
        spin = (g.k * a + g.off) * @rad

        near =
          near
          |> faces(g, spin, best, state)
          |> walls(g, spin, best, state)
          |> offer_all(g.bore, best)

        {near, [spin | spins]}
      end)

    spins = spins |> Enum.reverse() |> List.to_tuple()
    near = Enum.group_by(near, &elem(&1, 0), &elem(&1, 1))
    exact = &exact_depth(state, spins, &1)

    decided =
      for {k, keys} <- near,
          top = :atomics.get(best, k + 1),
          cands = candidates(top, keys),
          cands |> Enum.map(&class/1) |> Enum.uniq() |> length() > 1,
          into: %{},
          do: {k, settle(cands, exact)}

    lines =
      for row <- 0..(@rows - 1) do
        for col <- 0..(@cols - 1) do
          cell(best, near, decided, exact, row, col, env.paper)
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # -- plotting --------------------------------------------------------------

  # Keeps the largest key per sample, and every key that came within the
  # margin of the largest at the time, as {sample, key}.
  @compile {:inline, offer: 4}
  defp offer(best, k, key, near) do
    cur = :atomics.get(best, k + 1)

    if cur == 0 do
      :atomics.put(best, k + 1, key)
      near
    else
      dk = bsr(key, @depth_shift)
      dc = bsr(cur, @depth_shift)

      cond do
        dk > dc + @margin ->
          :atomics.put(best, k + 1, key)
          near

        dk > dc ->
          :atomics.put(best, k + 1, key)
          [{k, cur} | near]

        dk >= dc - @margin ->
          [{k, key} | near]

        true ->
          near
      end
    end
  end

  defp offer_all(near, [], _best), do: near

  defp offer_all(near, [{k, key} | rest], best),
    do: offer_all(offer(best, k, key, near), rest, best)

  # The face turns as a whole, so each point is its resting place rotated by
  # the spin: an affine map of (r cos th, r sin th) to the sample's column and
  # row and the depth. Where that lands within eps of a sample's edge the
  # point is placed exactly as upstream places it.
  defp faces(near, g, spin, best, %{view: {cy, sy, cx, sx}, left: left, high: high}) do
    cs = :math.cos(spin)
    ss = :math.sin(spin)
    hsy = g.h * sy
    hcy = g.h * cy
    s2 = @scale * 2

    # The rotated place is off by less than 1e-12 of a sample, more as the
    # angle grows; past any sane time every point is placed exactly.
    eps = if abs(spin) > 1.0e6, do: 2.0, else: 1.0e-9 + abs(spin) * 1.0e-12

    co = {
      (g.x * cy + hsy - left) * s2,
      cs * cy * s2,
      -ss * cy * s2,
      (high - g.y * cx - (g.x * sy - hcy) * sx) * @scale,
      -(ss * cx + cs * sy * sx) * @scale,
      -(cs * cx - ss * sy * sx) * @scale,
      (g.y * sx + (hcy - g.x * sy) * cx + @offset) * @quanta,
      (ss * sx - cs * sy * cx) * @quanta,
      (cs * sx + ss * sy * cx) * @quanta,
      eps,
      1 - eps
    }

    face(g.face, co, {g, spin}, g.face_class, best, near)
  end

  defp face([], _co, _g, _class, _best, near), do: near

  # The guards tell the compiler these are floats, which makes the
  # arithmetic several times faster.
  defp face(
         [{u, v, r, th, idx} | rest],
         {c0, cu, cv, r0, ru, rv, q0, qu, qv, lo, hi} = co,
         g,
         class,
         best,
         near
       )
       when is_float(u) and is_float(v) and is_float(c0) and is_float(cu) and is_float(cv) and
              is_float(r0) and is_float(ru) and is_float(rv) and is_float(q0) and is_float(qu) and
              is_float(qv) and is_float(lo) and is_float(hi) do
    ca = c0 + u * cu + v * cv
    ra = r0 + u * ru + v * rv
    col = floor(ca)
    row = floor(ra)
    fc = ca - col
    fr = ra - row

    near =
      if fc < lo or fc > hi or fr < lo or fr > hi do
        {gear, spin} = g

        case face_exact(gear, r, th, spin) do
          {nil, _} -> near
          {k, d} -> offer(best, k, key(d, class, idx), near)
        end
      else
        face_offer(col, row, trunc(q0 + u * qu + v * qv), class, idx, best, near)
      end

    face(rest, co, g, class, best, near)
  end

  defp face_offer(col, row, _dq, _class, _idx, _best, near)
       when col < 0 or col >= @w or row < 0 or row >= @h,
       do: near

  defp face_offer(col, row, dq, class, idx, best, near) do
    key = bor(bor(bsl(dq, @depth_shift), bsl(class, @class_shift)), idx)
    offer(best, row * @w + col, key, near)
  end

  # A face point exactly as upstream plots it: its sample (or nil) and depth.
  defp face_exact(g, r, th, spin) do
    x = g.x + r * :math.cos(th + spin)
    y = g.y + r * :math.sin(th + spin)
    {sample(x, y, g.h, g.view, g.left, g.high), depth(x, y, g.h, g.view)}
  end

  # The outer wall: each angle a column of points up the wall. Along a column
  # the depth only grows, so of a run of points in one sample only the last
  # can matter. A stretch facing away is never drawn.
  defp walls(near, g, spin, best, %{view: view, light: light, left: left, high: high}) do
    {cy, sy, cx, sx} = view

    Enum.reduce(g.walls, near, fn {th, r, dr, l, base}, near ->
      c = :math.cos(th + spin)
      s = :math.sin(th + spin)

      case wall_tone((r * c + dr * s) / l, (r * s - dr * c) / l, view, light) do
        nil ->
          near

        tone ->
          x = g.x + r * c
          y = g.y + r * s
          col = {x * cy, x * sy, y * cx, y * sx, left, high, sx, cx}
          wall_column(g.zs, col, -1, nil, g.i * 5 + tone, base, best, near)
      end
    end)
  end

  defp wall_column([], col, k, last, class, base, best, near),
    do: flush(col, k, last, class, base, best, near)

  defp wall_column(
         [{zsy, zcy, zi} | rest],
         {xcy, xsy, ycx, _, left, high, sx, _} = col,
         k,
         last,
         class,
         base,
         best,
         near
       )
       when is_float(zsy) and is_float(zcy) and is_float(xcy) and is_float(xsy) and
              is_float(ycx) and is_float(left) and is_float(high) and is_float(sx) do
    c = floor((xcy + zsy - left) * @scale * 2.0)
    r = floor((high - (ycx + (xsy - zcy) * sx)) * @scale)
    here = if c < 0 or c >= @w or r < 0 or r >= @h, do: -1, else: r * @w + c

    if here == k do
      wall_column(rest, col, k, {zcy, zi}, class, base, best, near)
    else
      near = flush(col, k, last, class, base, best, near)
      wall_column(rest, col, here, {zcy, zi}, class, base, best, near)
    end
  end

  defp flush(_col, -1, _last, _class, _base, _best, near), do: near

  defp flush({_, xsy, _, ysx, _, _, _, cx}, k, {zcy, zi}, class, base, best, near) do
    d = ysx + (zcy - xsy) * cx
    offer(best, k, key(d, class, base + zi), near)
  end

  # -- settling --------------------------------------------------------------

  defp class(key), do: band(bsr(key, @class_shift), 15)
  defp order(key), do: band(key, 0x1FFFF)

  # The keys of a sample within the margin of its largest.
  defp candidates(top, keys) do
    floor = bsr(top, @depth_shift) - @margin
    Enum.uniq([top | Enum.filter(keys, &(bsr(&1, @depth_shift) >= floor))])
  end

  # Upstream's rule, exactly: the largest rounded depth, and of the points
  # that round to it, the last one above it, else the first.
  defp settle(cands, exact) do
    ps = Enum.map(cands, fn key -> {order(key), class(key), exact.(order(key))} end)
    m = ps |> Enum.map(&JSMath.fround(elem(&1, 2))) |> Enum.max()
    j = ps |> Enum.filter(&(JSMath.fround(elem(&1, 2)) == m)) |> Enum.sort()

    {_, class, _} =
      case Enum.filter(j, &(elem(&1, 2) > m)) do
        [] -> hd(j)
        above -> List.last(above)
      end

    {class, m}
  end

  # A point's depth exactly as upstream computes it, from its place in the
  # plotting order.
  defp exact_depth(state, spins, idx) do
    g = state.gears |> Enum.filter(&(&1.face_lo <= idx)) |> List.last()
    spin = elem(spins, g.i)

    cond do
      idx < g.wall_lo ->
        {_, _, r, th, _} = elem(g.face_at, idx - g.face_lo)
        {_, d} = face_exact(g, r, th, spin)
        d

      idx < g.bore_lo ->
        local = idx - g.wall_lo
        {th, r, _, _} = elem(g.wall_at, div(local, g.nz))
        z = elem(g.z_at, rem(local, g.nz))
        depth(g.x + r * :math.cos(th + spin), g.y + r * :math.sin(th + spin), z, g.view)

      true ->
        Map.fetch!(g.bore_d, idx)
    end
  end

  # -- cells -----------------------------------------------------------------

  # A cell shows the shade that covers most of its four samples, the nearer
  # on a tie, and nothing if fewer than two are covered, so the gaps between
  # teeth stay open. On paper the shades turn over, so ink is still shadow.
  defp cell(best, near, decided, exact, row, col, paper) do
    ks = [
      2 * row * @w + 2 * col,
      2 * row * @w + 2 * col + 1,
      (2 * row + 1) * @w + 2 * col,
      (2 * row + 1) * @w + 2 * col + 1
    ]

    covered = for k <- ks, s = rough(best, decided, k), s != nil, do: s

    {n, c} =
      case pick_shade(covered) do
        {n, c, false} ->
          {n, c}

        {_, _, true} ->
          exact_samples = for k <- ks, s = precise(best, near, decided, exact, k), s != nil, do: s
          {n, c, _} = pick_shade(exact_samples)
          {n, c}
      end

    if n < 2 do
      " "
    else
      v = rem(c, 5)
      elem(@shade, if(paper, do: 5 - v, else: v))
    end
  end

  # A sample's class and depth, the depth to within a float32 step.
  defp rough(best, decided, k) do
    case decided do
      %{^k => s} ->
        s

      _ ->
        case :atomics.get(best, k + 1) do
          0 -> nil
          key -> {class(key), bsr(key, @depth_shift) / @quanta - @offset}
        end
    end
  end

  # A sample's class and depth exactly as upstream stores them.
  defp precise(best, near, decided, exact, k) do
    case decided do
      %{^k => s} ->
        s

      _ ->
        case :atomics.get(best, k + 1) do
          0 ->
            nil

          top ->
            m =
              top
              |> candidates(Map.get(near, k, []))
              |> Enum.map(&JSMath.fround(exact.(order(&1))))
              |> Enum.max()

            {class(top), m}
        end
    end
  end

  # Upstream's vote, sample by sample, flagging a tie on depth that rough
  # depths cannot settle.
  defp pick_shade(samples) do
    {n, best, _, unsure} =
      Enum.reduce(samples, {0, nil, %{}, false}, fn {c, d}, {n, best, seen, unsure} ->
        seen = Map.update(seen, c, {1, d}, fn {cn, near} -> {cn + 1, max(near, d)} end)
        {cn, cnear} = seen[c]

        case best do
          nil ->
            {n + 1, c, seen, unsure}

          b ->
            {bn, bnear} = seen[b]

            cond do
              cn > bn ->
                {n + 1, c, seen, unsure}

              cn == bn and c != b and abs(cnear - bnear) <= @margin_depth ->
                {n + 1, if(cnear > bnear, do: c, else: b), seen, true}

              cn == bn and cnear > bnear ->
                {n + 1, c, seen, unsure}

              true ->
                {n + 1, b, seen, unsure}
            end
        end
      end)

    {n, best, unsure}
  end
end
