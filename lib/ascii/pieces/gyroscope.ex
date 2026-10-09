defmodule Ascii.Pieces.Gyroscope do
  @moduledoc """
  Gimbals swing round a spinning rotor whose axle holds still.

  A flywheel hung in three gimbal rings on a post and foot. The outer ring
  turns and the gimbals swing so the rotor's axle keeps its line.

  Ported from `src/pieces/gyroscope.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  import Bitwise

  @meta %Ascii.Meta{
    name: "gyroscope",
    category: :shapes,
    note: "gimbals swing round a spinning rotor whose axle holds still",
    cols: 60,
    rows: 32,
    fps: 30,
    loop: 8
  }

  @cols 60
  @rows 32
  @ramp {".", ",", "-", ":", ";", "=", "+", "*", "#", "%", "@"}
  @tau :math.pi() * 2
  # Eye to centre, and the projection scale: columns per unit at the centre.
  @k2 8.0
  @k1 22 * @k2
  @ro 1
  @rm 0.74
  @ri 0.5
  @tube 0.065
  # Flywheel radius, half thickness, rounded rim as a fraction.
  @rotor 0.35
  @half 0.07
  @rim 0.26
  @n 14
  # A depth buffer entry: the float32 depth's bits, then the point's index.
  @idx_bits 20
  @idx_mask 0xFFFFF

  @impl true
  def meta, do: @meta

  defp rx(a) do
    c = :math.cos(a)
    s = :math.sin(a)
    {1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c}
  end

  defp ry(a) do
    c = :math.cos(a)
    s = :math.sin(a)
    {c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c}
  end

  defp mul(a, b) do
    List.to_tuple(
      for i <- 0..2,
          j <- 0..2,
          do:
            elem(a, i * 3) * elem(b, j) + elem(a, i * 3 + 1) * elem(b, 3 + j) +
              elem(a, i * 3 + 2) * elem(b, 6 + j)
    )
  end

  defp unit(x, y, z) do
    m = JSMath.hypot(x, y, z)
    {x / m, y / m, z / m}
  end

  @impl true
  def init(_options) do
    cv = List.to_tuple(for j <- 0..(@n - 1), do: :math.cos(j / @n * @tau))
    sv = List.to_tuple(for j <- 0..(@n - 1), do: :math.sin(j / @n * @tau))
    {l0, l1, l2} = light = unit(-0.5, 0.8, -0.6)
    # Looking down a little.
    view = rx(-0.3)

    # Every point upstream plots, in its order, by the frame it turns with:
    # the stand (0), the outer ring (1), the middle (2), the inner (3) and
    # the rotor (4).
    segments = [
      # The stand: a knob on top, a post and a round foot below.
      {0,
       pin(1, @ro, @ro + 0.13, 0.04, cv, sv) ++
         pin(1, @ro + 0.13, @ro + 0.2, 0.07, cv, sv) ++
         pin(1, -@ro - 0.13, -@ro, 0.04, cv, sv) ++
         pin(1, -1.4, -@ro - 0.1, 0.055, cv, sv) ++
         disc(-1.42, 0.12, 0.02) ++ disc(-1.46, 0.38, 0.025)},
      {1,
       pin(0, @rm, @ro, 0.032, cv, sv) ++
         pin(0, -@ro, -@rm, 0.032, cv, sv) ++ ring(1, @ro, 400, cv, sv)},
      {2,
       pin(1, @ri, @rm, 0.032, cv, sv) ++
         pin(1, -@rm, -@ri, 0.032, cv, sv) ++ ring(2, @rm, 320, cv, sv)},
      {3, ring(3, @ri, 240, cv, sv)},
      {4, rotor(cv, sv)}
    ]

    {segments, _} =
      Enum.map_reduce(segments, 0, fn {seg, points}, next ->
        {Enum.with_index(points, next) |> Enum.map(fn {p, i} -> {seg, p, i} end),
         next + length(points)}
      end)

    [stand | turning] = segments

    points =
      segments |> Enum.concat() |> Enum.map(fn {seg, p, _} -> Tuple.insert_at(p, 9, seg) end)

    %{
      # The rotor's fixed direction, stand frame.
      axle: unit(-0.55, 0.42, -0.72),
      view: view,
      light: light,
      # Halfway between light and eye.
      half: unit(l0, l1, l2 - 1),
      points: List.to_tuple(points),
      stand: stand_depths(stand, view),
      turning:
        Enum.map(turning, fn [{seg, _, _} | _] = ps ->
          {seg, Enum.map(ps, fn {_, {x, y, z, _, _, _, _, _, _}, i} -> {x, y, z, i} end)}
        end)
    }
  end

  # The stand never moves, so the depth buffer as it leaves it is known.
  defp stand_depths(stand, view) do
    buf = :atomics.new(@cols * @rows, signed: false)

    plot_all(
      Enum.map(stand, fn {_, {x, y, z, _, _, _, _, _, _}, i} -> {x, y, z, i} end),
      view,
      buf
    )

    for c <- 0..(@cols * @rows - 1), (v = :atomics.get(buf, c + 1)) != 0, do: {c + 1, v}
  end

  @impl true
  def frame(state, t, env) do
    # The outer ring turns about the stand; the middle and inner rings take
    # whatever angles keep the axle on its fixed line.
    {ax0, ax1, ax2} = state.axle
    a = 0.9 * :math.sin((t / 8 - 1 / 12) * @tau)
    ca = :math.cos(a)
    sa = :math.sin(a)
    wx = ca * ax0 - sa * ax2
    wy = ax1
    wz = sa * ax0 + ca * ax2
    c = :math.acos(max(-1, min(1, wx)))
    b = :math.atan2(wy, -wz)
    mo = mul(state.view, ry(a))
    mm = mul(mo, rx(b))
    mi = mul(mm, ry(c))
    mats = {state.view, mo, mm, mi, mul(mi, rx(t * 1.25 * @tau))}

    # The depth buffer, a scratch array for this frame: per cell the float32
    # depth's bits, then the point. Upstream shades every point that passes
    # the depth test, but only the last one in a cell shows, so only those
    # are shaded here.
    buf = :atomics.new(@cols * @rows, signed: false)
    for {c, v} <- state.stand, do: :atomics.put(buf, c, v)
    for {seg, ps} <- state.turning, do: plot_all(ps, elem(mats, seg), buf)

    cells =
      List.to_tuple(
        for c <- 1..(@cols * @rows) do
          case :atomics.get(buf, c) do
            0 -> nil
            v -> drawn(v, mats, state)
          end
        end
      )

    lines =
      for r <- 0..(@rows - 1) do
        for col <- 0..(@cols - 1), do: cell(cells, col, col + r * @cols, env.paper)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cell(cells, col, k, paper) do
    case elem(cells, k) do
      nil ->
        " "

      {d, part, i} ->
        # Where one part passes in front of another, leave a blank cell
        # beside the nearer one so each ring keeps its own edge.
        if part != 0 and
             ((col > 0 and in_front?(elem(cells, k - 1), part, d)) or
                (col < @cols - 1 and in_front?(elem(cells, k + 1), part, d))),
           do: " ",
           else: elem(@ramp, if(paper, do: tuple_size(@ramp) - 1 - i, else: i))
    end
  end

  defp in_front?({dn, pn, _}, part, d), do: pn != 0 and pn != part and dn > d + 0.0008
  defp in_front?(nil, _part, _d), do: false

  # The point that drew a cell: its depth, its part and its shade.
  defp drawn(v, mats, state) do
    <<d::float-32>> = <<bsr(v, @idx_bits)::32>>
    {x, y, z, nx, ny, nz, k, gain, id, seg} = elem(state.points, band(v, @idx_mask))
    {w0, w1, w2, w3, w4, w5, w6, w7, w8} = elem(mats, seg)
    bz = w6 * x + w7 * y + w8 * z
    nnx = w0 * nx + w1 * ny + w2 * nz
    nny = w3 * nx + w4 * ny + w5 * nz
    nnz = w6 * nx + w7 * ny + w8 * nz
    # Light whichever side faces us.
    m = if(nnz > 0, do: -1, else: 1) / hypot(nnx, nny, nnz)
    nnx = nnx * m
    nny = nny * m
    nnz = nnz * m
    {l0, l1, l2} = state.light
    {h0, h1, h2} = state.half
    diff = (nnx * l0 + nny * l1 + nnz * l2 + 1) / 2
    lit = {0.08 + 0.7 * (diff * diff), 0.55 + 0.45 * min(1, max(0, 0.5 - 0.6 * bz)), k, gain}
    {d, id, shade(lit, nnx * h0 + nny * h1 + nnz * h2)}
  end

  # The ramp index for a specular highlight of max(0, dot) ** 24. That power
  # is costly, so it is bracketed first by repeated squaring (good to 1e-14);
  # the index only grows with it, so when both ends give the same index that
  # is the index, and only otherwise is Math.pow's exact value taken.
  defp shade(lit, dot) when dot <= 0, do: level(lit, 0)

  defp shade(lit, dot) do
    s8 = dot * dot * (dot * dot) * (dot * dot * (dot * dot))
    s24 = s8 * s8 * s8
    lo = level(lit, max(0.0, s24 * (1 - 1.0e-13) - 1.0e-300))
    hi = level(lit, s24 * (1 + 1.0e-13) + 1.0e-300)
    if lo == hi, do: lo, else: level(lit, :math.pow(dot, 24))
  end

  defp level({base, near, k, gain}, spec) do
    JSMath.round(min(1, (base + 0.45 * spec) * near * k * gain) * (tuple_size(@ramp) - 1))
  end

  # Math.hypot of three numbers as V8 computes it (see JSMath.hypot_list/1),
  # inline: scaled by the largest, summed with Kahan's compensation.
  defp hypot(a, b, c) do
    a = abs(a)
    b = abs(b)
    c = abs(c)
    m = max(max(a, b), c)
    {sum, comp} = kahan(0.0, 0.0, a / m)
    {sum, comp} = kahan(sum, comp, b / m)
    {sum, _} = kahan(sum, comp, c / m)
    :math.sqrt(sum) * m
  end

  defp kahan(sum, comp, n) do
    summand = n * n - comp
    pre = sum + summand
    {pre, pre - sum - summand}
  end

  # Each point turned and projected; the nearer one keeps the cell. Depths
  # are a Float32Array upstream, so a point beats the stored float32 value.
  defp plot_all([], _w, _buf), do: :ok

  # The guards tell the compiler these are floats, which makes the
  # arithmetic several times faster.
  defp plot_all([{x, y, z, idx} | rest], {w0, w1, w2, w3, w4, w5, w6, w7, w8} = w, buf)
       when is_float(x) and is_float(y) and is_float(z) and is_float(w0) and is_float(w1) and
              is_float(w2) and is_float(w3) and is_float(w4) and is_float(w5) and is_float(w6) and
              is_float(w7) and is_float(w8) do
    bx = w0 * x + w1 * y + w2 * z
    by = w3 * x + w4 * y + w5 * z
    bz = w6 * x + w7 * y + w8 * z
    ooz = 1.0 / (@k2 + bz)
    col = floor(@cols / 2 + @k1 * ooz * bx)
    row = floor(@rows / 2 - 2 - @k1 * 0.5 * ooz * by)

    if col >= 0 and col < @cols and row >= 0 and row < @rows do
      c = col + row * @cols + 1
      <<d::float-32>> = <<bsr(:atomics.get(buf, c), @idx_bits)::32>>

      if ooz > d do
        <<bits::32>> = <<ooz::float-32>>
        :atomics.put(buf, c, bor(bsl(bits, @idx_bits), idx))
      end
    end

    plot_all(rest, w, buf)
  end

  defp steps(from, step, test), do: from |> Stream.iterate(&(&1 + step)) |> Enum.take_while(test)

  # The points, as {x, y, z, nx, ny, nz, k, gain, part}. Shade is scaled by
  # k, so the rotor's faces print bright and its spoke dark; pins are
  # polished, so they print brighter.

  # A torus in the local xy plane.
  defp ring(id, r, steps, cv, sv) do
    for i <- 0..(steps - 1), j <- 0..(@n - 1) do
      cu = :math.cos(i / steps * @tau)
      su = :math.sin(i / steps * @tau)
      h = r + @tube * elem(cv, j)

      {h * cu, h * su, @tube * elem(sv, j), elem(cv, j) * cu, elem(cv, j) * su, elem(sv, j), 1, 1,
       id}
    end
  end

  # A pin of radius r along the local x (ax 0) or y (ax 1) axis, from a to b.
  defp pin(ax, a, b, r, cv, sv) do
    n = ceil(abs(b - a) / 0.02)

    for i <- 0..n, j <- 0..(@n - 1) do
      p = a + (b - a) * i / n

      if ax == 0,
        do: {p, r * elem(cv, j), r * elem(sv, j), 0, elem(cv, j), elem(sv, j), 1, 1.5, 0},
        else: {r * elem(cv, j), p, r * elem(sv, j), elem(cv, j), 0, elem(sv, j), 1, 1.5, 0}
    end
  end

  # A flat disc lying level, centred at height y: top face and rim.
  defp disc(y, r, h) do
    for k <- 0..119 do
      ca = :math.cos(k / 120 * @tau)
      sa = :math.sin(k / 120 * @tau)

      for(
        p <- steps(0, 0.02, &(&1 <= r)),
        do: {p * ca, y + h, p * sa, 0.12 * ca * (p / r), 1, 0.12 * sa * (p / r), 1, 1, 0}
      ) ++ for q <- steps(-h, 0.02, &(&1 <= h)), do: {r * ca, y + q, r * sa, ca, 0, sa, 1, 1, 0}
    end
    |> Enum.concat()
  end

  # A solid flywheel facing along local x: flat faces rounding off at the
  # rim, one dark spoke so the spin shows, and the axle through its hub.
  defp rotor(cv, sv) do
    wheel =
      for k <- 0..159 do
        th = k / 160 * @tau
        ca = :math.cos(th)
        sa = :math.sin(th)
        spoke = min(th, @tau - th) < 0.22

        faces =
          for p <- steps(0, 0.012, &(&1 <= @rotor + 1.0e-9)) do
            f = p / @rotor
            bev = if f > 1 - @rim, do: 0.9 * (f - 1 + @rim) / @rim, else: 0
            shade = if spoke and f > 0.3 and f < 0.95, do: 0.35, else: 1.35

            [
              {@half, p * ca, p * sa, 1, bev * ca, bev * sa, shade, 1, 4},
              {-@half, p * ca, p * sa, -1, bev * ca, bev * sa, shade, 1, 4}
            ]
          end

        rim =
          for x <- steps(-@half, 0.02, &(&1 <= @half + 1.0e-9)),
              do: {x, @rotor * ca, @rotor * sa, 0, ca, sa, 1, 1, 4}

        Enum.concat(faces) ++ rim
      end

    # Hub, axle through the inner ring's bearings, and the bearings.
    Enum.concat(wheel) ++
      pin(0, -@half - 0.05, @half + 0.05, 0.065, cv, sv) ++
      pin(0, -@ri - 0.1, @ri + 0.1, 0.05, cv, sv) ++
      pin(0, @ri - 0.06, @ri + 0.04, 0.07, cv, sv) ++
      pin(0, -@ri - 0.04, -@ri + 0.06, 0.07, cv, sv)
  end
end
