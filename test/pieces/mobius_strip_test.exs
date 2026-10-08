defmodule AsciiArt.Pieces.MobiusStripTest.Upstream do
  @moduledoc false
  # A plain port of upstream's mobius-strip.ts, line for line: every point is
  # plotted in upstream's order into a Float32 depth buffer (a map here) and
  # shaded as it is written. No fast paths, no margins.

  alias AsciiArt.JSMath

  @cols 58
  @rows 20
  @ramp {".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @w 0.46
  @nu 720
  @nv 40
  @d 6
  @aspect 0.5
  @gap 0.3

  def init(_options) do
    points = for i <- 0..(@nu - 1), j <- 0..(@nv - 1), do: point(i, j)
    pt = List.to_tuple(points)

    {ex, ey} =
      for s <- steps(0, 0.05, &(&1 < 6.283)),
          tt <- steps(0.8, 0.05, &(&1 <= 1.21)),
          reduce: {0, 0} do
        {ex, ey} ->
          {_, _, hw, hh} = box(pt, :math.cos(s), :math.sin(s), :math.cos(tt), :math.sin(tt))
          {max(ex, hw), max(ey, hh)}
      end

    lm = JSMath.hypot(-0.35, 0.8, 0.5)
    fm = JSMath.hypot(0.3, -0.3, 0.9)

    %{
      points: pt,
      k: min((@cols - 3) / 2 / ex, (@rows - 2) / 2 / @aspect / ey),
      light: {-0.35 / lm, 0.8 / lm, 0.5 / lm},
      fill: {0.3 / fm, -0.3 / fm, 0.9 / fm}
    }
  end

  defp point(i, j) do
    u = i / @nu * 6.2832
    cu = :math.cos(u)
    su = :math.sin(u)
    ch = :math.cos(u / 2)
    sh = :math.sin(u / 2)
    v = -@w + 2 * @w * j / (@nv - 1)
    h = 1 + v * ch
    ux = -(v / 2) * sh * cu - h * su
    uy = -(v / 2) * sh * su + h * cu
    uz = v / 2 * ch
    {vx, vy, vz} = {ch * cu, ch * su, sh}
    mx = uy * vz - uz * vy
    my = uz * vx - ux * vz
    mz = ux * vy - uy * vx
    m = JSMath.hypot(mx, my, mz)
    rim = if j == 0 or j == @nv - 1, do: 0.45, else: 1

    Enum.map([h * cu, h * su, v * sh, mx / m, my / m, mz / m, 0.1 * ch, rim], &JSMath.fround/1)
    |> List.to_tuple()
  end

  defp steps(from, step, test), do: from |> Stream.iterate(&(&1 + step)) |> Enum.take_while(test)

  defp box(pt, cs, ss, ct, st) do
    {x0, x1, y0, y1} =
      0
      |> steps(11, &(&1 < @nu * @nv))
      |> Enum.reduce({9, -9, 9, -9}, fn k, {x0, x1, y0, y1} ->
        {px, py, pz, _, _, _, _, _} = elem(pt, k)
        x = cs * px - ss * py
        w = ss * px + cs * py
        y = ct * w + st * pz
        z = -st * w + ct * pz
        bx = x / (@d - z)
        by = y / (@d - z)

        {if(bx < x0, do: bx, else: x0), if(bx > x1, do: bx, else: x1),
         if(by < y0, do: by, else: y0), if(by > y1, do: by, else: y1)}
      end)

    {(x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2}
  end

  def frame(state, t, env) do
    s = 2.6 + t * 0.35
    tt = 1 - 0.2 * :math.cos(t * 0.3)
    view = {:math.cos(s), :math.sin(s), :math.cos(tt), :math.sin(tt)}
    {cs, ss, ct, st} = view
    {mx, my, _, _} = box(state.points, cs, ss, ct, st)

    buf =
      Enum.reduce(0..(@nu * @nv - 1), %{}, fn k, buf ->
        plot(buf, elem(state.points, k), k, view, {mx, my}, state, env.paper)
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: cell(buf, c, r)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp plot(
         buf,
         {px, py, pz, _, _, _, _, _} = p,
         k,
         {cs, ss, ct, st} = view,
         {mx, my},
         state,
         paper
       ) do
    x = cs * px - ss * py
    y0 = ss * px + cs * py
    y = ct * y0 + st * pz
    z = -st * y0 + ct * pz
    ooz = 1 / (@d - z)
    col = floor(@cols / 2 + state.k * (ooz * x - mx))
    row = floor(@rows / 2 - state.k * @aspect * (ooz * y - my))
    q = col + row * @cols

    cond do
      col < 0 or col >= @cols or row < 0 or row >= @rows -> buf
      match?(%{^q => {d, _, _}} when z + 10 <= d, buf) -> buf
      true -> Map.put(buf, q, {JSMath.fround(z + 10), div(k, @nv), glyph(p, view, state, paper)})
    end
  end

  defp glyph({_, _, _, nx, ny, nz, tone, rim}, {cs, ss, ct, st}, state, paper) do
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
    i = JSMath.round(max(0, min(1, lit)) * 8)
    elem(@ramp, if(paper, do: 8 - i, else: i))
  end

  # Clear a cell of band wherever a part further round the loop passes in front of it.
  defp cell(buf, c, r) do
    q = c + r * @cols

    case buf do
      %{^q => {d, along, ch}} ->
        cut =
          (c > 0 and over?(buf, q - 1, d, along)) or
            (c < @cols - 1 and over?(buf, q + 1, d, along)) or
            (r > 0 and over?(buf, q - @cols, d, along)) or
            (r < @rows - 1 and over?(buf, q + @cols, d, along))

        if cut, do: " ", else: ch

      _ ->
        " "
    end
  end

  defp over?(buf, p, d, along) do
    case buf do
      %{^p => {dp, ap, _}} ->
        s = abs(ap - along)
        dp > d + @gap and min(s, @nu - s) > @nu / 12

      _ ->
        false
    end
  end
end

defmodule AsciiArt.Pieces.MobiusStripTest do
  use ExUnit.Case, async: true
  use AsciiArt.ContractCase, piece: AsciiArt.Pieces.MobiusStrip
  use AsciiArt.GoldenCase, slug: "mobius-strip", piece: AsciiArt.Pieces.MobiusStrip

  alias AsciiArt.Pieces.MobiusStrip
  alias AsciiArt.Pieces.MobiusStripTest.Upstream

  # The port plots into a scratch depth buffer of float32 bits and shades
  # only the point that keeps each cell. Upstream below, plainly, shades
  # every point as it is written.

  setup_all do
    %{piece: MobiusStrip.init(MobiusStrip.meta().options), upstream: Upstream.init(%{})}
  end

  property "frames match a plain port of upstream at random times", context do
    check all(
            times <- list_of(float(min: 0.0, max: 120.0), min_length: 1, max_length: 3),
            paper <- boolean(),
            max_runs: 120
          ) do
      assert_same(context, times, paper)
    end
  end

  # At 768/30 s a point lands in a cell whose stored float32 depth rounded
  # down below an earlier point's, and beats it by less than a float32 step:
  # it wins only because the comparison is with the stored, rounded value.
  test "a point just above a rounded-down float32 depth wins, as upstream's does", context do
    assert_same(context, [768 / 30], false)
  end

  defp assert_same(%{piece: piece, upstream: upstream}, times, paper) do
    ours = play(MobiusStrip, piece, times, paper)
    theirs = play(Upstream, upstream, times, paper)

    for {t, a, b} <- Enum.zip([times, ours, theirs]) do
      assert a == b, "t = #{t}, paper: #{paper}\n\nport:\n#{a}\n\nupstream:\n#{b}"
    end
  end

  # Each a fresh instance, threading its state through the times in turn.
  defp play(mod, state, times, paper) do
    env = %AsciiArt.Env{cols: 58, rows: 20, paper: paper}

    {frames, _} =
      Enum.map_reduce(times, state, fn t, state ->
        {io, nil, state} = mod.frame(state, t * 1.0, env)
        {IO.iodata_to_binary(io), state}
      end)

    frames
  end
end
