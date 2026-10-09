defmodule Ascii.Pieces.TorusKnot do
  @moduledoc """
  A trefoil knot drawn as a lit tube, turning slowly.

  A (2,3) trefoil knot as a lit tube, z-buffered so the strands pass over and
  under each other, turning slowly about its axis.

  Ported from `src/pieces/torus-knot.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  import Bitwise

  @meta %Ascii.Meta{
    name: "torus knot",
    category: :shapes,
    note: "a trefoil knot drawn as a lit tube, turning slowly",
    cols: 60,
    rows: 28,
    fps: 30
  }

  @cols 60
  @rows 28
  @ramp {".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @tube 0.28
  @nu 720
  @nv 32
  # Eye to centre.
  @d 11.0
  @aspect 0.5
  # A depth step this big, between far apart parts of the knot, is a crossing.
  @gap @tube * 0.9
  # A depth buffer entry: the float32 depth's bits, then the point's index.
  @idx_bits 15
  @idx_mask 0x7FFF

  @impl true
  def meta, do: @meta

  # The knot's centre line: twice round the z axis, three times through the hole.
  defp curve(u) do
    r = 2 + :math.cos(3 * u)
    {r * :math.cos(2 * u), r * :math.sin(2 * u), -:math.sin(3 * u)}
  end

  @impl true
  def init(_options) do
    # Surface points and normals, built once; each frame only rotates them.
    # Every value is stored in a Float32Array upstream.
    points =
      for i <- 0..(@nu - 1), point <- ring(i / @nu * 6.2832), do: point

    sparse =
      points |> Enum.take_every(7) |> Enum.map(fn {px, py, pz, _, _, _} -> {px, py, pz} end)

    {mx, my} =
      for a <- steps(0, 0.1, &(&1 < 6.283)),
          tt <- steps(0.2, 0.07, &(&1 <= 0.77)),
          reduce: {0, 0} do
        {mx, my} ->
          extent(sparse, :math.cos(a), :math.sin(a), :math.cos(tt), :math.sin(tt), mx, my)
      end

    m = JSMath.hypot(-0.35, 0.45, 1)
    {lx, ly, lz} = {-0.35 / m, 0.45 / m, 1 / m}
    # Half vector for a specular glint, between the light and the eye (+z).
    hm = JSMath.hypot(lx, ly, lz + 1)

    %{
      normals:
        points |> Enum.map(fn {_, _, _, nx, ny, nz} -> {nx, ny, nz} end) |> List.to_tuple(),
      points:
        points
        |> Enum.with_index()
        |> Enum.map(fn {{px, py, pz, nx, ny, nz}, k} -> {px, py, pz, nx, ny, nz, k} end),
      k: min((@cols - 2) / 2 / mx, (@rows - 2) / 2 / @aspect / my),
      light: {lx, ly, lz},
      half: {lx / hm, ly / hm, (lz + 1) / hm}
    }
  end

  defp ring(u) do
    {c0, c1, c2} = curve(u)
    {d0, d1, d2} = curve(u + 1.0e-3)
    tx = d0 - c0
    ty = d1 - c1
    tz = d2 - c2
    tl = JSMath.hypot(tx, ty, tz)
    tx = tx / tl
    ty = ty / tl
    tz = tz / tl
    # A frame across the tube: one axis in the xy plane, the other from a cross product.
    al = JSMath.hypot(ty, -tx)
    ax = ty / al
    ay = -tx / al
    bx = -tz * ay
    by = tz * ax
    bz = tx * ay - ty * ax

    for j <- 0..(@nv - 1) do
      v = j / @nv * 6.2832
      cv = :math.cos(v)
      sv = :math.sin(v)
      nx = JSMath.fround(ax * cv + bx * sv)
      ny = JSMath.fround(ay * cv + by * sv)
      nz = JSMath.fround(bz * sv)

      {JSMath.fround(c0 + @tube * nx), JSMath.fround(c1 + @tube * ny),
       JSMath.fround(c2 + @tube * nz), nx, ny, nz}
    end
  end

  defp steps(from, step, test), do: from |> Stream.iterate(&(&1 + step)) |> Enum.take_while(test)

  # The guards tell the compiler these are floats, which makes the
  # arithmetic several times faster.
  defp extent([], _cs, _ss, _ct, _st, mx, my), do: {mx, my}

  defp extent([{px, py, pz} | rest], cs, ss, ct, st, mx, my)
       when is_float(px) and is_float(py) and is_float(pz) and is_float(cs) and is_float(ss) and
              is_float(ct) and is_float(st) do
    x = cs * px - ss * py
    y = ct * (ss * px + cs * py) - st * pz
    z = st * (ss * px + cs * py) + ct * pz
    ex = abs(x) / (@d - z)
    ey = abs(y) / (@d - z)
    extent(rest, cs, ss, ct, st, if(ex > mx, do: ex, else: mx), if(ey > my, do: ey, else: my))
  end

  @impl true
  def frame(state, t, env) do
    # Spin about the knot's own axis, nodding between 0.2 and 0.76 rad of tilt
    # so the over and under strands separate in depth as it turns.
    s = t * 0.3
    tt = 0.48 - 0.28 * :math.cos(t * 0.35)
    cs = :math.cos(s)
    ss = :math.sin(s)
    ct = :math.cos(tt)
    st = :math.sin(tt)
    rot = {cs, -ss, ct * ss, ct * cs, -st, st * ss, st * cs, ct}

    # The depth buffer, a scratch array for this frame: per cell the float32
    # depth's bits, then the point. Upstream shades every point that passes
    # the depth test, but only the last one in a cell shows, so only those
    # are shaded here.
    buf = :atomics.new(@cols * @rows, signed: false)
    plot_all(state.points, rot, state.k, buf)

    cells =
      List.to_tuple(
        for q <- 1..(@cols * @rows) do
          case :atomics.get(buf, q) do
            0 -> nil
            v -> drawn(v, rot, state)
          end
        end
      )

    # Where one strand passes over another, clear the one cell of the lower
    # strand beside the upper one's outline, so the crossing reads as a gap.
    kept =
      for q <- 0..(@cols * @rows - 1),
          elem(cells, q) != nil,
          not cut?(cells, q),
          into: %{},
          do: {q, elem(elem(cells, q), 2)}

    # Drop the small scraps a gap can leave, so each strand stays one piece.
    kept = drop_scraps(kept)
    last = tuple_size(@ramp) - 1

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          case Map.get(kept, c + r * @cols) do
            nil -> " "
            i -> elem(@ramp, if(env.paper, do: last - i, else: i))
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cut?(cells, q) do
    c = rem(q, @cols)
    here = elem(cells, q)

    (c > 0 and over?(here, elem(cells, q - 1))) or
      (c < @cols - 1 and over?(here, elem(cells, q + 1))) or
      (q >= @cols and over?(here, elem(cells, q - @cols))) or
      (q < @cols * @rows - @cols and over?(here, elem(cells, q + @cols)))
  end

  defp over?(_here, nil), do: false

  defp over?({dq, aq, _}, {dp, ap, _}) do
    s = abs(ap - aq)
    dp > dq + @gap and min(s, @nu - s) > @nu / 16
  end

  defp drop_scraps(kept) do
    {kept, _} =
      kept
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce({kept, MapSet.new()}, fn q, {kept, seen} ->
        if q in seen do
          {kept, seen}
        else
          part = component([q], MapSet.new([q]), kept)
          kept = if MapSet.size(part) < 7, do: Map.drop(kept, MapSet.to_list(part)), else: kept
          {kept, MapSet.union(seen, part)}
        end
      end)

    kept
  end

  defp component([], part, _kept), do: part

  defp component([p | stack], part, kept) do
    c = rem(p, @cols)

    next =
      for o <- [
            if(c > 0, do: p - 1, else: -1),
            if(c < @cols - 1, do: p + 1, else: -1),
            p - @cols,
            p + @cols
          ],
          o >= 0,
          Map.has_key?(kept, o),
          o not in part,
          do: o

    component(next ++ stack, Enum.reduce(next, part, &MapSet.put(&2, &1)), kept)
  end

  # The point that drew a cell: its depth, which step of the centre line it
  # shows, and its shade.
  defp drawn(v, {r00, r01, r10, r11, r12, r20, r21, r22}, state) do
    <<d::float-32>> = <<bsr(v, @idx_bits)::32>>
    k = band(v, @idx_mask)
    {nx, ny, nz} = elem(state.normals, k)
    wz = r20 * nx + r21 * ny + r22 * nz
    wx = r00 * nx + r01 * ny
    wy = r10 * nx + r11 * ny + r12 * nz
    {lx, ly, lz} = state.light
    {hx, hy, hz} = state.half
    diff = max(0, wx * lx + wy * ly + wz * lz)
    {d, div(k, @nv), gloss(0.08 + diff * 0.8, wx * hx + wy * hy + wz * hz)}
  end

  # The ramp index for a glint of max(0, dot) ** 24. That power is costly,
  # so it is bracketed first by repeated squaring (good to 1e-14); the index
  # only grows with it, so when both ends give the same index that is the
  # index, and only otherwise is Math.pow's exact value taken.
  defp gloss(lit, dot) when dot <= 0, do: level(lit, 0)

  defp gloss(lit, dot) do
    s8 = dot * dot * (dot * dot) * (dot * dot * (dot * dot))
    s24 = s8 * s8 * s8
    lo = level(lit, max(0.0, s24 * (1 - 1.0e-13) - 1.0e-300))
    hi = level(lit, s24 * (1 + 1.0e-13) + 1.0e-300)
    if lo == hi, do: lo, else: level(lit, :math.pow(dot, 24))
  end

  defp level(lit, spec), do: JSMath.round(min(1, lit + spec * 0.5) * (tuple_size(@ramp) - 1))

  # Each point turned and projected; the nearer one keeps the cell. Depths
  # are a Float32Array upstream, so a point beats the stored float32 value.
  defp plot_all([], _rot, _k, _buf), do: :ok

  defp plot_all(
         [{px, py, pz, nx, ny, nz, idx} | rest],
         {r00, r01, r10, r11, r12, r20, r21, r22} = rot,
         k,
         buf
       )
       when is_float(px) and is_float(py) and is_float(pz) and is_float(nx) and is_float(ny) and
              is_float(nz) and is_float(r00) and is_float(r01) and is_float(r10) and
              is_float(r11) and is_float(r12) and is_float(r20) and is_float(r21) and
              is_float(r22) and is_float(k) do
    # Faces away from the eye.
    if r20 * nx + r21 * ny + r22 * nz >= -0.15, do: plot(px, py, pz, idx, rot, k, buf)

    plot_all(rest, rot, k, buf)
  end

  defp plot(px, py, pz, idx, {r00, r01, r10, r11, r12, r20, r21, r22}, k, buf) do
    x = r00 * px + r01 * py
    y = r10 * px + r11 * py + r12 * pz
    z = r20 * px + r21 * py + r22 * pz
    ooz = 1.0 / (@d - z)
    col = floor(@cols / 2 + k * ooz * x)
    row = floor(@rows / 2 - k * @aspect * ooz * y)

    if col >= 0 and col < @cols and row >= 0 and row < @rows do
      q = col + row * @cols + 1
      zz = z + 20.0
      <<d::float-32>> = <<bsr(:atomics.get(buf, q), @idx_bits)::32>>

      if zz > d do
        <<bits::32>> = <<zz::float-32>>
        :atomics.put(buf, q, bor(bsl(bits, @idx_bits), idx))
      end
    end
  end
end
