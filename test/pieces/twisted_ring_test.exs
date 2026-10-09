defmodule Ascii.Pieces.TwistedRingTest.Upstream do
  @moduledoc false
  # A plain port of upstream's twisted-ring.ts, line for line: every point is
  # placed, tested and plotted in upstream's order into Float32 buffers (maps
  # here), each corner point taking its stroke as it is written. No fast
  # paths, no margins.

  alias Ascii.JSMath

  @cols 46
  @rows 21
  @w @cols * 2
  @h @rows * 2
  @face {".", ":", "+", "*", "#", "@"}
  @aspect 0.5
  @r 0.75
  @ap 0.22
  @twist 3
  @eye 6
  @scale 9.2
  @lift 0.5
  @laps 720
  @across 14

  defp unit({x, y, z}) do
    m = JSMath.hypot(x, y, z)
    {x / m, y / m, z / m}
  end

  def init(_options) do
    {l0, l1, l2} = light = unit({-0.5, 0.75, 0.6})
    %{light: light, half: unit({l0, l1, l2 + 1}), tilt: {:math.cos(0.92), :math.sin(0.92)}}
  end

  def frame(state, t, env) do
    p = 0.4 + 0.32 * t
    {ct, st} = state.tilt
    view = {:math.cos(p), :math.sin(p), ct, st}

    depth =
      for i <- 0..(@laps - 1), f <- 0..3, reduce: %{} do
        depth -> face(depth, i, f, view, state)
      end

    ink =
      for f <- 0..3, reduce: %{} do
        ink -> corner(ink, f, view, depth)
      end

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: cell(ink, depth, r, c, env.paper)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # A point on the ring: its place on the sample grid, its nearness, and where it is.
  defp place({cs, ss, ct, st}, ca, sa, qr, qy) do
    x = (@r + qr) * ca
    z = (@r + qr) * sa
    wx = cs * x + ss * z
    z1 = -ss * x + cs * z
    wy = ct * qy - st * z1
    wz = st * qy + ct * z1
    ooz = 1 / (@eye - wz)
    k = @scale * @eye * ooz
    {2 * (@cols / 2 + k * wx / @aspect), 2 * (@rows / 2 - @lift - k * wy), ooz, wx, wy, wz}
  end

  defp normal({cs, ss, ct, st}, ca, sa, n) do
    ox = :math.cos(n) * ca
    oz = :math.cos(n) * sa
    z1 = -ss * ox + cs * oz
    {cs * ox + ss * oz, ct * :math.sin(n) - st * z1, st * :math.sin(n) + ct * z1}
  end

  defp toward?({q0, q1, q2}, {_, _, _, wx, wy, wz}), do: -q0 * wx - q1 * wy + q2 * (@eye - wz) > 0

  defp face(depth, i, f, view, state) do
    a = i / @laps * 2 * :math.pi() - :math.pi()
    {ca, sa} = {:math.cos(a), :math.sin(a)}
    n = @twist * a / 4 + (2 * f + 1) * :math.pi() / 4
    {cn, sn} = {:math.cos(n), :math.sin(n)}
    {q0, q1, q2} = q = normal(view, ca, sa, n)
    {l0, l1, l2} = state.light
    {h0, h1, h2} = state.half
    tone = mark(q0 * h0 + q1 * h1 + q2 * h2, max(0, q0 * l0 + q1 * l1 + q2 * l2))

    Enum.reduce(0..@across, depth, fn j, depth ->
      s = 2 * j / @across - 1
      pt = place(view, ca, sa, @ap * (cn - s * sn), @ap * (sn + s * cn))
      {sx, sy, ooz, _, _, _} = pt
      {c, r} = {floor(sx), floor(sy)}
      o = r * @w + c

      cond do
        not toward?(q, pt) -> depth
        c < 0 or c >= @w or r < 0 or r >= @h -> depth
        ooz > depth_at(depth, o) -> Map.put(depth, o, {JSMath.fround(ooz), tone})
        true -> depth
      end
    end)
  end

  defp mark(h, d) do
    cond do
      h > 0.998 -> 5
      d < 0.2 -> 0
      d < 0.45 -> 1
      d < 0.7 -> 2
      d < 0.9 -> 3
      true -> 4
    end
  end

  defp depth_at(depth, o), do: depth |> Map.get(o, {0, 0}) |> elem(0)

  defp corner(ink, f, view, depth) do
    n = @laps * 2
    d = @ap * :math.sqrt(2)

    {ink, _, _} =
      Enum.reduce(0..n, {ink, 0, 0}, fn i, {ink, px, py} ->
        a = i / n * 2 * :math.pi() - :math.pi()
        m = @twist * a / 4 + f * :math.pi() / 2
        {ca, sa} = {:math.cos(a), :math.sin(a)}
        {sx, sy, _, _, _, _} = pt = place(view, ca, sa, d * :math.cos(m), d * :math.sin(m))

        ink =
          if i > 0 and toward?(normal(view, ca, sa, m - :math.pi() / 4), pt) and
               toward?(normal(view, ca, sa, m + :math.pi() / 4), pt),
             do: ink_at(ink, pt, sx - px, sy - py, depth),
             else: ink

        {ink, sx, sy}
      end)

    ink
  end

  defp ink_at(ink, {sx, sy, ooz, _, _, _}, dx, dy, depth) do
    {c, r} = {floor(sx), floor(sy)}
    o = r * @w + c
    cell = div(r, 2) * @cols + div(c, 2)

    cond do
      c < 0 or c >= @w or r < 0 or r >= @h -> ink
      depth_at(depth, o) == 0 or ooz < depth_at(depth, o) - 0.0025 -> ink
      ooz <= ink |> Map.get(cell, {0, ""}) |> elem(0) -> ink
      true -> Map.put(ink, cell, {JSMath.fround(ooz), stroke(dx, dy)})
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

  # Each cell takes the nearest of its samples, or a corner's line.
  defp cell(ink, depth, r, c, paper) do
    o = 2 * r * @w + 2 * c
    here = r * @cols + c

    case ink do
      %{^here => {_, ch}} ->
        ch

      _ ->
        hits = for q <- [o, o + 1, o + @w, o + @w + 1], Map.has_key?(depth, q), do: depth[q]

        case hits do
          [_, _ | _] ->
            {_, tone} =
              Enum.reduce(hits, fn {d, t}, {bd, bt} -> if d > bd, do: {d, t}, else: {bd, bt} end)

            elem(@face, if(paper, do: 5 - tone, else: tone))

          _ ->
            " "
        end
    end
  end
end

defmodule Ascii.Pieces.TwistedRingTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.TwistedRing
  use Ascii.GoldenCase, slug: "twisted-ring", piece: Ascii.Pieces.TwistedRing

  alias Ascii.Pieces.TwistedRing
  alias Ascii.Pieces.TwistedRingTest.Upstream

  # The port skips, or draws without testing, whole strips of a face whose
  # two edges are clearly on one side of the eye, and shades only the point
  # that keeps each cell. Upstream below, plainly, tests every point. No
  # frame in 6,601 tried (every 1/30 s to 120 s, and 3,000 random times to
  # 1,000 s) has a strip within the margin, so there is no fixed time to pin.

  setup_all do
    %{piece: TwistedRing.init(TwistedRing.meta().options), upstream: Upstream.init(%{})}
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
    ours = play(TwistedRing, piece, times, paper)
    theirs = play(Upstream, upstream, times, paper)

    for {t, a, b} <- Enum.zip([times, ours, theirs]) do
      assert a == b, "t = #{t}, paper: #{paper}\n\nport:\n#{a}\n\nupstream:\n#{b}"
    end
  end

  # Each a fresh instance, threading its state through the times in turn.
  defp play(mod, state, times, paper) do
    env = %Ascii.Env{cols: 46, rows: 21, paper: paper}

    {frames, _} =
      Enum.map_reduce(times, state, fn t, state ->
        {io, nil, state} = mod.frame(state, t * 1.0, env)
        {IO.iodata_to_binary(io), state}
      end)

    frames
  end
end
