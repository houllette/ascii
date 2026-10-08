defmodule AsciiArt.Pieces.GyroscopeTest.Upstream do
  @moduledoc false
  # A plain port of upstream's gyroscope.ts, line for line: every point is
  # plotted in upstream's order into a Float32 depth buffer (a map here) and
  # shaded as it is written, with Math.hypot and Math.pow. No fast paths, no
  # margins.

  alias AsciiArt.JSMath

  @cols 60
  @rows 32
  @ramp {".", ",", "-", ":", ";", "=", "+", "*", "#", "%", "@"}
  @tau :math.pi() * 2
  # Eye to centre, and the projection scale: columns per unit at the centre.
  @k2 8
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

  def init(_options) do
    cv = List.to_tuple(for j <- 0..(@n - 1), do: :math.cos(j / @n * @tau))
    sv = List.to_tuple(for j <- 0..(@n - 1), do: :math.sin(j / @n * @tau))
    {l0, l1, l2} = light = unit(-0.5, 0.8, -0.6)

    %{
      # The rotor's fixed direction, stand frame; looking down a little.
      axle: unit(-0.55, 0.42, -0.72),
      view: rx(-0.3),
      light: light,
      # Halfway between light and eye.
      half: unit(l0, l1, l2 - 1),
      cv: cv,
      sv: sv
    }
  end

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
    mr = mul(mi, rx(t * 1.25 * @tau))

    s = %{state: state, paper: env.paper, w: state.view, id: 0, gain: 1, buf: %{}}

    # The stand: a knob on top, a post and a round foot below.
    s =
      s
      |> pin(1, @ro, @ro + 0.13, 0.04)
      |> pin(1, @ro + 0.13, @ro + 0.2, 0.07)
      |> pin(1, -@ro - 0.13, -@ro, 0.04)
      |> pin(1, -1.4, -@ro - 0.1, 0.055)
      |> disc(-1.42, 0.12, 0.02)
      |> disc(-1.46, 0.38, 0.025)
      |> Map.put(:w, mo)
      |> pin(0, @rm, @ro, 0.032)
      |> pin(0, -@ro, -@rm, 0.032)
      |> Map.put(:id, 1)
      |> ring(@ro, 400)
      |> Map.merge(%{w: mm, id: 0})
      |> pin(1, @ri, @rm, 0.032)
      |> pin(1, -@rm, -@ri, 0.032)
      |> Map.put(:id, 2)
      |> ring(@rm, 320)
      |> Map.merge(%{w: mi, id: 3})
      |> ring(@ri, 240)
      |> Map.merge(%{w: mr, id: 4})
      |> rotor()

    buf = s.buf

    # Where one part passes in front of another, leave a blank cell beside
    # the nearer one so each ring keeps its own edge.
    gaps =
      for {k, {d, part, _}} <- buf,
          part != 0,
          x = rem(k, @cols),
          n <- [if(x > 0, do: k - 1, else: -1), if(x < @cols - 1, do: k + 1, else: -1)],
          n >= 0,
          match?(%{^n => {dn, pn, _}} when pn != 0 and pn != part and dn > d + 0.0008, buf),
          into: MapSet.new(),
          do: k

    lines =
      for r <- 0..(@rows - 1) do
        for col <- 0..(@cols - 1) do
          k = col + r * @cols

          if MapSet.member?(gaps, k), do: " ", else: buf |> Map.get(k, {0, 0, " "}) |> elem(2)
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # Shade is scaled by k, so the rotor's faces print bright and its spoke dark.
  defp plot(s, x, y, z, nx, ny, nz, k \\ 1) do
    {w0, w1, w2, w3, w4, w5, w6, w7, w8} = s.w
    bx = w0 * x + w1 * y + w2 * z
    by = w3 * x + w4 * y + w5 * z
    bz = w6 * x + w7 * y + w8 * z
    ooz = 1 / (@k2 + bz)
    col = floor(@cols / 2 + @k1 * ooz * bx)
    row = floor(@rows / 2 - 2 - @k1 * 0.5 * ooz * by)
    c = col + row * @cols

    cond do
      col < 0 or col >= @cols or row < 0 or row >= @rows ->
        s

      match?(%{^c => {d, _, _}} when ooz <= d, s.buf) ->
        s

      true ->
        nnx = w0 * nx + w1 * ny + w2 * nz
        nny = w3 * nx + w4 * ny + w5 * nz
        nnz = w6 * nx + w7 * ny + w8 * nz
        # Light whichever side faces us.
        m = if(nnz > 0, do: -1, else: 1) / JSMath.hypot(nnx, nny, nnz)
        nnx = nnx * m
        nny = nny * m
        nnz = nnz * m
        {l0, l1, l2} = s.state.light
        {h0, h1, h2} = s.state.half
        diff = (nnx * l0 + nny * l1 + nnz * l2 + 1) / 2
        diff = diff * diff
        spec = :math.pow(max(0, nnx * h0 + nny * h1 + nnz * h2), 24)
        near = 0.55 + 0.45 * min(1, max(0, 0.5 - 0.6 * bz))
        last = tuple_size(@ramp) - 1
        i = JSMath.round(min(1, (0.08 + 0.7 * diff + 0.45 * spec) * near * k * s.gain) * last)
        ch = elem(@ramp, if(s.paper, do: last - i, else: i))
        %{s | buf: Map.put(s.buf, c, {JSMath.fround(ooz), s.id, ch})}
    end
  end

  # A torus in the local xy plane.
  defp ring(s, r, steps) do
    %{cv: cv, sv: sv} = s.state

    for i <- 0..(steps - 1), j <- 0..(@n - 1), reduce: s do
      s ->
        cu = :math.cos(i / steps * @tau)
        su = :math.sin(i / steps * @tau)
        h = r + @tube * elem(cv, j)

        plot(
          s,
          h * cu,
          h * su,
          @tube * elem(sv, j),
          elem(cv, j) * cu,
          elem(cv, j) * su,
          elem(sv, j)
        )
    end
  end

  # A pin of radius r along the local x (ax 0) or y (ax 1) axis, from a to b.
  defp pin(s, ax, a, b, r) do
    %{cv: cv, sv: sv} = s.state
    n = ceil(abs(b - a) / 0.02)
    s = %{s | gain: 1.5}

    s =
      for i <- 0..n, j <- 0..(@n - 1), reduce: s do
        s ->
          p = a + (b - a) * i / n

          if ax == 0,
            do: plot(s, p, r * elem(cv, j), r * elem(sv, j), 0, elem(cv, j), elem(sv, j)),
            else: plot(s, r * elem(cv, j), p, r * elem(sv, j), elem(cv, j), 0, elem(sv, j))
      end

    %{s | gain: 1}
  end

  defp steps(from, step, test), do: from |> Stream.iterate(&(&1 + step)) |> Enum.take_while(test)

  # A flat disc lying level, centred at height y: top face and rim.
  defp disc(s, y, r, h) do
    for k <- 0..119, reduce: s do
      s ->
        ca = :math.cos(k / 120 * @tau)
        sa = :math.sin(k / 120 * @tau)

        s =
          Enum.reduce(steps(0, 0.02, &(&1 <= r)), s, fn p, s ->
            plot(s, p * ca, y + h, p * sa, 0.12 * ca * (p / r), 1, 0.12 * sa * (p / r))
          end)

        Enum.reduce(steps(-h, 0.02, &(&1 <= h)), s, fn q, s ->
          plot(s, r * ca, y + q, r * sa, ca, 0, sa)
        end)
    end
  end

  # A solid flywheel facing along local x: flat faces rounding off at the
  # rim, one dark spoke so the spin shows, and the axle through its hub.
  defp rotor(s) do
    s =
      for k <- 0..159, reduce: s do
        s ->
          th = k / 160 * @tau
          ca = :math.cos(th)
          sa = :math.sin(th)
          spoke = min(th, @tau - th) < 0.22

          s =
            Enum.reduce(steps(0, 0.012, &(&1 <= @rotor + 1.0e-9)), s, fn p, s ->
              f = p / @rotor
              bev = if f > 1 - @rim, do: 0.9 * (f - 1 + @rim) / @rim, else: 0
              shade = if spoke and f > 0.3 and f < 0.95, do: 0.35, else: 1.35

              s
              |> plot(@half, p * ca, p * sa, 1, bev * ca, bev * sa, shade)
              |> plot(-@half, p * ca, p * sa, -1, bev * ca, bev * sa, shade)
            end)

          Enum.reduce(steps(-@half, 0.02, &(&1 <= @half + 1.0e-9)), s, fn x, s ->
            plot(s, x, @rotor * ca, @rotor * sa, 0, ca, sa)
          end)
      end

    %{s | id: 0}
    # Hub, axle through the inner ring's bearings, and the bearings.
    |> pin(0, -@half - 0.05, @half + 0.05, 0.065)
    |> pin(0, -@ri - 0.1, @ri + 0.1, 0.05)
    |> pin(0, @ri - 0.06, @ri + 0.04, 0.07)
    |> pin(0, -@ri - 0.04, -@ri + 0.06, 0.07)
  end
end

defmodule AsciiArt.Pieces.GyroscopeTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.Gyroscope
  use AsciiArt.GoldenCase, slug: "gyroscope", piece: AsciiArt.Pieces.Gyroscope

  alias AsciiArt.Pieces.Gyroscope
  alias AsciiArt.Pieces.GyroscopeTest.Upstream

  # The port plots into a scratch depth buffer of float32 bits, shades only
  # the point that keeps each cell, and brackets Math.pow before taking it
  # exactly. Upstream below, plainly, shades every point as it is written.
  # No frame in 6,601 tried (every 1/30 s to 120 s, and 3,000 random times to
  # 1,000 s) needs the exact Math.pow, so there is no fixed time to pin here.

  setup_all do
    %{piece: Gyroscope.init(Gyroscope.meta().options), upstream: Upstream.init(%{})}
  end

  property "frames match a plain port of upstream at random times", context do
    check all(
            times <- list_of(float(min: 0.0, max: 120.0), min_length: 1, max_length: 3),
            paper <- boolean(),
            max_runs: 100
          ) do
      assert_same(context, times, paper)
    end
  end

  defp assert_same(%{piece: piece, upstream: upstream}, times, paper) do
    ours = play(Gyroscope, piece, times, paper)
    theirs = play(Upstream, upstream, times, paper)

    for {t, a, b} <- Enum.zip([times, ours, theirs]) do
      assert a == b, "t = #{t}, paper: #{paper}\n\nport:\n#{a}\n\nupstream:\n#{b}"
    end
  end

  # Each a fresh instance, threading its state through the times in turn.
  defp play(mod, state, times, paper) do
    env = %AsciiArt.Env{cols: 60, rows: 32, paper: paper}

    {frames, _} =
      Enum.map_reduce(times, state, fn t, state ->
        {io, nil, state} = mod.frame(state, t * 1.0, env)
        {IO.iodata_to_binary(io), state}
      end)

    frames
  end
end
