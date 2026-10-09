defmodule Ascii.Pieces.MobiusStrip do
  @moduledoc """
  A mobius strip turning and nodding, lit from above.

  A band with one half twist, spinning about its axis while it slowly nods.
  Z-buffered; the two faces take the light differently.

  Ported from `src/pieces/mobius-strip.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  import Bitwise

  @meta %Ascii.Meta{
    name: "mobius strip",
    category: :shapes,
    note: "a mobius strip turning and nodding, lit from above",
    cols: 58,
    rows: 20,
    fps: 30
  }

  @cols 58
  @rows 20
  @ramp {".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # Half the band's width, the ring's radius being 1.
  @w 0.46
  @nu 720
  @nv 40
  @d 6.0
  @aspect 0.5
  @gap 0.3
  # A depth buffer entry: the float32 depth's bits, then the point's index.
  @idx_bits 15
  @idx_mask 0x7FFF

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    # The standard strip: the band turns half a turn, evenly, on its way
    # round. Every value is stored in a Float32Array upstream.
    points =
      for i <- 0..(@nu - 1), j <- 0..(@nv - 1) do
        u = i / @nu * 6.2832
        cu = :math.cos(u)
        su = :math.sin(u)
        ch = :math.cos(u / 2)
        sh = :math.sin(u / 2)
        v = -@w + 2 * @w * j / (@nv - 1)
        h = 1 + v * ch
        # Normal from the two tangents, d/du and d/dv.
        ux = -(v / 2) * sh * cu - h * su
        uy = -(v / 2) * sh * su + h * cu
        uz = v / 2 * ch
        vx = ch * cu
        vy = ch * su
        vz = sh
        mx = uy * vz - uz * vy
        my = uz * vx - ux * vz
        mz = ux * vy - uy * vx
        m = JSMath.hypot(mx, my, mz)

        # The two sides of the band, told apart by a shade that runs twice
        # round: at the seam, where the normal flips, it flips too, so it
        # never jumps. The edge is drawn a little darker, a thin outline that
        # never outweighs the band.
        {f32(h * cu), f32(h * su), f32(v * sh), f32(mx / m), f32(my / m), f32(mz / m),
         f32(0.1 * ch), f32(if(j == 0 or j == @nv - 1, do: 0.45, else: 1))}
      end

    positions = Enum.map(points, fn {x, y, z, _, _, _, _, _} -> {x, y, z} end)
    sparse = positions |> Enum.take_every(11)

    # The strip is wider where it lies flat than where it stands up, so each
    # frame is centred on its own bounds.
    {ex, ey} =
      for s <- steps(0, 0.05, &(&1 < 6.283)),
          tt <- steps(0.8, 0.05, &(&1 <= 1.21)),
          reduce: {0, 0} do
        {ex, ey} ->
          {_, _, hw, hh} =
            box(sparse, :math.cos(s), :math.sin(s), :math.cos(tt), :math.sin(tt))

          {max(ex, hw), max(ey, hh)}
      end

    # A key light from above, so the band's upper side reads light and its
    # underside dark where the twist turns it toward the eye, and a weak fill.
    lm = JSMath.hypot(-0.35, 0.8, 0.5)
    fm = JSMath.hypot(0.3, -0.3, 0.9)

    %{
      points: List.to_tuple(points),
      positions:
        positions |> Enum.with_index() |> Enum.map(fn {{x, y, z}, k} -> {x, y, z, k} end),
      sparse: sparse,
      k: min((@cols - 3) / 2 / ex, (@rows - 2) / 2 / @aspect / ey),
      light: {-0.35 / lm, 0.8 / lm, 0.5 / lm},
      fill: {0.3 / fm, -0.3 / fm, 0.9 / fm}
    }
  end

  defp f32(x), do: JSMath.fround(x)

  defp steps(from, step, test), do: from |> Stream.iterate(&(&1 + step)) |> Enum.take_while(test)

  # [centre x, centre y, half width, half height] of every eleventh point.
  defp box(sparse, cs, ss, ct, st) do
    {x0, x1, y0, y1} = bounds(sparse, cs, ss, ct, st, 9.0, -9.0, 9.0, -9.0)
    {(x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2}
  end

  # The guards tell the compiler these are floats, which makes the
  # arithmetic several times faster.
  defp bounds([], _cs, _ss, _ct, _st, x0, x1, y0, y1), do: {x0, x1, y0, y1}

  defp bounds([{px, py, pz} | rest], cs, ss, ct, st, x0, x1, y0, y1)
       when is_float(px) and is_float(py) and is_float(pz) and is_float(cs) and is_float(ss) and
              is_float(ct) and is_float(st) and is_float(x0) and is_float(x1) and is_float(y0) and
              is_float(y1) do
    x = cs * px - ss * py
    w = ss * px + cs * py
    y = ct * w + st * pz
    z = -st * w + ct * pz
    bx = x / (@d - z)
    by = y / (@d - z)

    bounds(
      rest,
      cs,
      ss,
      ct,
      st,
      if(bx < x0, do: bx, else: x0),
      if(bx > x1, do: bx, else: x1),
      if(by < y0, do: by, else: y0),
      if(by > y1, do: by, else: y1)
    )
  end

  @impl true
  def frame(state, t, env) do
    # Spin about the ring's axis, which nods between 0.8 and 1.2 rad from the line of sight.
    s = 2.6 + t * 0.35
    tt = 1 - 0.2 * :math.cos(t * 0.3)
    view = {:math.cos(s), :math.sin(s), :math.cos(tt), :math.sin(tt)}
    {cs, ss, ct, st} = view
    {mx, my, _, _} = box(state.sparse, cs, ss, ct, st)

    # The depth buffer, a scratch array for this frame: per cell the float32
    # depth's bits, then the point. Upstream shades every point that passes
    # the depth test, but only the last one in a cell shows, so only those
    # are shaded here.
    buf = :atomics.new(@cols * @rows, signed: false)
    plot_all(state.positions, {cs, ss, ct, st, mx, my, state.k}, buf)

    cells =
      List.to_tuple(
        for q <- 1..(@cols * @rows) do
          case :atomics.get(buf, q) do
            0 -> nil
            v -> drawn(v, view, state)
          end
        end
      )

    # Clear a cell of band wherever a part further round the loop passes in
    # front of it, so the layers stay apart.
    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: cell(cells, c, r, env.paper)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cell(cells, c, r, paper) do
    q = c + r * @cols

    case elem(cells, q) do
      nil ->
        " "

      {d, _along, i} = here ->
        cut =
          d > 0 and
            ((c > 0 and over?(here, elem(cells, q - 1))) or
               (c < @cols - 1 and over?(here, elem(cells, q + 1))) or
               (r > 0 and over?(here, elem(cells, q - @cols))) or
               (r < @rows - 1 and over?(here, elem(cells, q + @cols))))

        cond do
          cut -> " "
          paper -> elem(@ramp, tuple_size(@ramp) - 1 - i)
          true -> elem(@ramp, i)
        end
    end
  end

  defp over?(_here, nil), do: false

  defp over?({dq, aq, _}, {dp, ap, _}) do
    s = abs(ap - aq)
    dp > dq + @gap and min(s, @nu - s) > @nu / 12
  end

  # The point that drew a cell: its depth, how far round the loop it is, and
  # its shade.
  defp drawn(v, {cs, ss, ct, st}, state) do
    <<d::float-32>> = <<bsr(v, @idx_bits)::32>>
    k = band(v, @idx_mask)
    {_, _, _, nx, ny, nz, tone, rim} = elem(state.points, k)
    wx = cs * nx - ss * ny
    w0 = ss * nx + cs * ny
    wy = ct * w0 + st * nz
    wz = -st * w0 + ct * nz
    # A band has no inside: light whichever side faces the eye.
    {wx, wy, wz, side} = if wz < 0, do: {-wx, -wy, -wz, -1}, else: {wx, wy, wz, 1}
    {lx, ly, lz} = state.light
    {fx, fy, fz} = state.fill
    diff = max(0, wx * lx + wy * ly + wz * lz)
    fill = max(0, wx * fx + wy * fy + wz * fz)
    lit = (0.06 + diff * 0.82 + fill * 0.22 + side * tone) * rim
    {d, div(k, @nv), JSMath.round(max(0, min(1, lit)) * (tuple_size(@ramp) - 1))}
  end

  # Each point turned and projected; the nearer one keeps the cell. Depths
  # are a Float32Array upstream, so a point beats the stored float32 value.
  defp plot_all([], _view, _buf), do: :ok

  defp plot_all([{px, py, pz, idx} | rest], {cs, ss, ct, st, mx, my, k} = view, buf)
       when is_float(px) and is_float(py) and is_float(pz) and is_float(cs) and is_float(ss) and
              is_float(ct) and is_float(st) and is_float(mx) and is_float(my) and is_float(k) do
    x = cs * px - ss * py
    y0 = ss * px + cs * py
    y = ct * y0 + st * pz
    z = -st * y0 + ct * pz
    ooz = 1.0 / (@d - z)
    col = floor(@cols / 2 + k * (ooz * x - mx))
    row = floor(@rows / 2 - k * @aspect * (ooz * y - my))

    if col >= 0 and col < @cols and row >= 0 and row < @rows do
      q = col + row * @cols + 1
      zz = z + 10.0
      <<d::float-32>> = <<bsr(:atomics.get(buf, q), @idx_bits)::32>>

      if zz > d do
        <<bits::32>> = <<zz::float-32>>
        :atomics.put(buf, q, bor(bsl(bits, @idx_bits), idx))
      end
    end

    plot_all(rest, view, buf)
  end
end
