defmodule Ascii.Pieces.TwistedRing do
  @moduledoc """
  A square ring twisted three quarters, so it has one face.

  A ring of square section that twists three quarters of a turn in one lap,
  so its four faces join into one. The faces are flat shaded and the corners
  between them inked as lines. Turned about its own axis.

  Ported from `src/pieces/twisted-ring.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  import Bitwise

  @meta %Ascii.Meta{
    name: "twisted ring",
    category: :shapes,
    note: "a square ring twisted three quarters, so it has one face",
    cols: 46,
    rows: 21,
    fps: 30
  }

  @cols 46
  @rows 21
  # Two samples a cell each way.
  @w @cols * 2
  @h @rows * 2
  # A face's mark by its light, least to most.
  @face {".", ":", "+", "*", "#", "@"}
  # Cell width over cell height.
  @aspect 0.5
  # Ring radius, and the section's apothem.
  @r 0.75
  @ap 0.22
  # Quarter turns of the section in one lap; any odd number gives one face.
  @twist 3
  # TILT from edge on; SCALE: rows per unit at the ring's centre.
  @tilt 0.92
  @eye 6.0
  @scale 9.2
  @focal @scale * @eye
  # Rows the ring sits above centre, since its near side looks bigger.
  @lift 0.5
  # Radians a second, and the angle at t = 0.
  @spin 0.32
  @p0 0.4
  # Samples round the ring and across each face.
  @laps 720
  @across 14
  # A depth buffer entry: the float32 depth's bits, then the face's mark.
  @tone_bits 3

  @impl true
  def meta, do: @meta

  defp unit({x, y, z}) do
    m = JSMath.hypot(x, y, z)
    {x / m, y / m, z / m}
  end

  @impl true
  def init(_options) do
    {l0, l1, l2} = light = unit({-0.5, 0.75, 0.6})
    tilt = {:math.cos(@tilt), :math.sin(@tilt)}

    # Face f's normal, in the plane of the section, turns as it goes round.
    # Everything but the spin is known here: per angle round the ring and
    # face, the normal before the spin and the points across the face.
    faces =
      for i <- 0..(@laps - 1), f <- 0..3 do
        a = i / @laps * 2 * :math.pi() - :math.pi()
        ca = :math.cos(a)
        sa = :math.sin(a)
        n = @twist * a / 4 + (2 * f + 1) * :math.pi() / 4
        cn = :math.cos(n)
        sn = :math.sin(n)

        points =
          for j <- 0..@across do
            s = 2 * j / @across - 1
            point(ca, sa, @ap * (cn - s * sn), @ap * (sn + s * cn))
          end

        {ox, oz, sn} = section(ca, sa, n)
        {x0, z0, qy0} = hd(points)
        {x1, z1, qy1} = List.last(points)
        {ox, oz, sn, x0, z0, qy0, x1, z1, qy1, points}
      end

    # The four corners, each a line round the ring.
    d = @ap * :math.sqrt(2)
    n = @laps * 2

    corners =
      for f <- 0..3 do
        for i <- 0..n do
          a = i / n * 2 * :math.pi() - :math.pi()
          m = @twist * a / 4 + f * :math.pi() / 2
          ca = :math.cos(a)
          sa = :math.sin(a)

          {x, z, qy} = point(ca, sa, d * :math.cos(m), d * :math.sin(m))
          {lox, loz, lsn} = section(ca, sa, m - :math.pi() / 4)
          {rox, roz, rsn} = section(ca, sa, m + :math.pi() / 4)
          {x, z, qy, lox, loz, lsn, rox, roz, rsn}
        end
      end

    %{
      tilt: tilt,
      light: light,
      half: unit({l0, l1, l2 + 1}),
      faces: faces,
      corners: corners
    }
  end

  # A point on the ring, at angle a round it and (qr, qy) in its section,
  # before the spin.
  defp point(ca, sa, qr, qy), do: {(@r + qr) * ca, (@r + qr) * sa, qy}

  # The normal at angle n in the section at angle a round the ring, before
  # the spin.
  defp section(ca, sa, n), do: {:math.cos(n) * ca, :math.cos(n) * sa, :math.sin(n)}

  @impl true
  def frame(state, t, env) do
    p = @p0 + @spin * t
    {ct, st} = state.tilt
    view = {:math.cos(p), :math.sin(p), ct, st}

    # The depth buffer, a scratch array for this frame: per sample the
    # float32 nearness's bits, then the mark.
    buf = :atomics.new(@w * @h, signed: false)

    {l0, l1, l2} = state.light
    {h0, h1, h2} = state.half
    faces(state.faces, view, {l0, l1, l2, h0, h1, h2}, buf)

    # The four corners, inked where both faces that meet there turn to the
    # eye and nothing nearer covers it, with the stroke that follows its way
    # across the cell.
    ink =
      state.corners
      |> Enum.reduce(%{}, fn corner, ink -> corner(corner, view, buf, ink) end)
      |> Map.new(fn {cell, {_, dx, dy}} -> {cell, stroke(dx, dy)} end)

    # Each cell takes the nearest of its samples, or a corner's line.
    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          case Map.get(ink, r * @cols + c) do
            nil -> shade(buf, 2 * r * @w + 2 * c, env.paper)
            ch -> ch
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp mark(q0, q1, q2, {l0, l1, l2, h0, h1, h2}) do
    d = max(0, q0 * l0 + q1 * l1 + q2 * l2)
    h = q0 * h0 + q1 * h1 + q2 * h2

    cond do
      h > 0.998 -> 5
      d < 0.2 -> 0
      d < 0.45 -> 1
      d < 0.7 -> 2
      d < 0.9 -> 3
      true -> 4
    end
  end

  # How far a point is on the side the face with world normal q turns to,
  # seen from the eye: upstream's test for drawing it, as is.
  @compile {:inline, facing: 7}
  defp facing(q0, q1, q2, x, z, qy, {cs, ss, ct, st}) do
    wx = cs * x + ss * z
    z1 = -ss * x + cs * z
    wy = ct * qy - st * z1
    wz = st * qy + ct * z1
    -q0 * wx - q1 * wy + q2 * (@eye - wz)
  end

  # Each face, a strip across the section at each angle round the ring.
  # Whether a point is on the side the face turns to is linear across the
  # strip, so when both its edges are clearly on one side (by 1e-12, far
  # past the rounding in the test) every point is: upstream would place
  # them all and draw none, or test each and draw all. A strip known to face
  # the eye goes on with no normal to test.
  defp faces([], _view, _light, _buf), do: :ok

  defp faces(
         [{ox, oz, sn, x0, z0, qy0, x1, z1, qy1, points} | rest],
         {cs, ss, ct, st} = view,
         light,
         buf
       )
       when is_float(ox) and is_float(oz) and is_float(sn) and is_float(x0) and is_float(z0) and
              is_float(qy0) and is_float(x1) and is_float(z1) and is_float(qy1) and
              is_float(cs) and is_float(ss) and is_float(ct) and is_float(st) do
    zn = -ss * ox + cs * oz
    q0 = cs * ox + ss * oz
    q1 = ct * sn - st * zn
    q2 = st * sn + ct * zn
    a = facing(q0, q1, q2, x0, z0, qy0, view)
    b = facing(q0, q1, q2, x1, z1, qy1, view)

    # One mark across the face's width, in four flat steps of light, and
    # the top one only where the face turns the light straight back.
    cond do
      a < -1.0e-12 and b < -1.0e-12 ->
        :ok

      a > 1.0e-12 and b > 1.0e-12 ->
        face(points, view, nil, mark(q0, q1, q2, light), buf)

      true ->
        face(points, view, {q0, q1, q2}, mark(q0, q1, q2, light), buf)
    end

    faces(rest, view, light, buf)
  end

  # The guards tell the compiler these are floats, which makes the
  # arithmetic several times faster.
  defp face([], _view, _q, _tone, _buf), do: :ok

  defp face([{x, z, qy} | rest], {cs, ss, ct, st} = view, q, tone, buf)
       when is_float(x) and is_float(z) and is_float(qy) and is_float(cs) and is_float(ss) and
              is_float(ct) and is_float(st) do
    wx = cs * x + ss * z
    z1 = -ss * x + cs * z
    wy = ct * qy - st * z1
    wz = st * qy + ct * z1

    # Upstream places every point, then drops those on a face turned away;
    # testing first gives the same picture.
    if toward?(q, wx, wy, wz), do: plot(wx, wy, wz, tone, buf)
    face(rest, view, q, tone, buf)
  end

  defp toward?(nil, _wx, _wy, _wz), do: true

  defp toward?({q0, q1, q2}, wx, wy, wz)
       when is_float(q0) and is_float(q1) and is_float(q2) and is_float(wx) and is_float(wy) and
              is_float(wz),
       do: -q0 * wx - q1 * wy + q2 * (@eye - wz) > 0

  defp plot(wx, wy, wz, tone, buf) do
    ooz = 1.0 / (@eye - wz)
    k = @focal * ooz
    c = floor(2 * (@cols / 2 + k * wx / @aspect))
    r = floor(2 * (@rows / 2 - @lift - k * wy))

    if c >= 0 and c < @w and r >= 0 and r < @h do
      o = r * @w + c + 1
      <<d::float-32>> = <<bsr(:atomics.get(buf, o), @tone_bits)::32>>

      if ooz > d do
        <<bits::32>> = <<ooz::float-32>>
        :atomics.put(buf, o, bor(bsl(bits, @tone_bits), tone))
      end
    end
  end

  defp depth_at(buf, o) do
    <<d::float-32>> = <<bsr(:atomics.get(buf, o + 1), @tone_bits)::32>>
    d
  end

  # One corner round the ring. Of the points that reach a cell, the last
  # shows; its stroke comes from its step from the point before it.
  defp corner(points, view, buf, ink), do: corner(points, view, buf, ink, nil, nil)

  defp corner([], _view, _buf, ink, _px, _py), do: ink

  defp corner(
         [{x, z, qy, lox, loz, lsn, rox, roz, rsn} | rest],
         {cs, ss, ct, st} = view,
         buf,
         ink,
         px,
         py
       )
       when is_float(x) and is_float(z) and is_float(qy) and is_float(cs) and is_float(ss) and
              is_float(ct) and is_float(st) do
    # A point spun about the axis and tipped toward the eye: its place on
    # the sample grid, its nearness, and where it is in the world.
    wx = cs * x + ss * z
    z1 = -ss * x + cs * z
    wy = ct * qy - st * z1
    wz = st * qy + ct * z1
    ooz = 1.0 / (@eye - wz)
    k = @focal * ooz
    sx = 2 * (@cols / 2 + k * wx / @aspect)
    sy = 2 * (@rows / 2 - @lift - k * wy)

    ink =
      if px != nil and turned?(lox, loz, lsn, view, wx, wy, wz) and
           turned?(rox, roz, rsn, view, wx, wy, wz),
         do: ink_at(ink, buf, sx, sy, ooz, sx - px, sy - py),
         else: ink

    corner(rest, view, buf, ink, sx, sy)
  end

  # Whether the face whose section normal is (ox, oz, sn) turns toward the
  # eye from a point.
  @compile {:inline, turned?: 7}
  defp turned?(ox, oz, sn, {cs, ss, ct, st}, wx, wy, wz) do
    z1 = -ss * ox + cs * oz
    q0 = cs * ox + ss * oz
    q1 = ct * sn - st * z1
    q2 = st * sn + ct * z1
    -q0 * wx - q1 * wy + q2 * (@eye - wz) > 0
  end

  defp ink_at(ink, buf, sx, sy, ooz, dx, dy) do
    c = floor(sx)
    r = floor(sy)
    o = r * @w + c

    with true <- c >= 0 and c < @w and r >= 0 and r < @h,
         d when d != 0 <- depth_at(buf, o),
         false <- ooz < d - 0.0025,
         cell = bsr(r, 1) * @cols + bsr(c, 1),
         false <- match?(%{^cell => {near, _, _}} when ooz <= near, ink) do
      Map.put(ink, cell, {JSMath.fround(ooz), dx, dy})
    else
      _ -> ink
    end
  end

  defp stroke(dx, dy) do
    ang = :math.atan2(abs(dy), abs(dx) * @aspect)

    cond do
      ang < 0.42 -> "-"
      ang > 1.2 -> "|"
      dx * dy < 0 -> "/"
      true -> "\\"
    end
  end

  defp shade(buf, o, paper) do
    {hits, best} =
      Enum.reduce([o, o + 1, o + @w, o + @w + 1], {0, nil}, fn q, {hits, best} ->
        case :atomics.get(buf, q + 1) do
          0 ->
            {hits, best}

          v ->
            <<d::float-32>> = <<bsr(v, @tone_bits)::32>>

            case best do
              {bd, _} when bd >= d -> {hits + 1, best}
              _ -> {hits + 1, {d, band(v, 7)}}
            end
        end
      end)

    case best do
      {_, tone} when hits >= 2 ->
        elem(@face, if(paper, do: tuple_size(@face) - 1 - tone, else: tone))

      _ ->
        " "
    end
  end
end
