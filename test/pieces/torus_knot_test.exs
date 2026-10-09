defmodule Ascii.Pieces.TorusKnotTest.Upstream do
  @moduledoc false
  # A plain port of upstream's torus-knot.ts, line for line: every point is
  # plotted in upstream's order into a Float32 depth buffer (a map here) and
  # shaded as it is written, with Math.pow. No fast paths, no margins.

  alias Ascii.JSMath

  @cols 60
  @rows 28
  @ramp {".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @tube 0.28
  @nu 720
  @nv 32
  @d 11
  @aspect 0.5

  defp curve(u) do
    r = 2 + :math.cos(3 * u)
    {r * :math.cos(2 * u), r * :math.sin(2 * u), -:math.sin(3 * u)}
  end

  def init(_options) do
    pt = List.to_tuple(for i <- 0..(@nu - 1), p <- ring(i), do: p)

    {mx, my} =
      for a <- steps(0, 0.1, &(&1 < 6.283)),
          tt <- steps(0.2, 0.07, &(&1 <= 0.77)),
          reduce: {0, 0} do
        acc -> extent(pt, :math.cos(a), :math.sin(a), :math.cos(tt), :math.sin(tt), acc)
      end

    m = JSMath.hypot(-0.35, 0.45, 1)
    {lx, ly, lz} = {-0.35 / m, 0.45 / m, 1 / m}
    hm = JSMath.hypot(lx, ly, lz + 1)

    %{
      points: pt,
      k: min((@cols - 2) / 2 / mx, (@rows - 2) / 2 / @aspect / my),
      light: {lx, ly, lz},
      half: {lx / hm, ly / hm, (lz + 1) / hm}
    }
  end

  defp ring(i) do
    u = i / @nu * 6.2832
    {c0, c1, c2} = curve(u)
    {d0, d1, d2} = curve(u + 1.0e-3)
    {tx, ty, tz} = {d0 - c0, d1 - c1, d2 - c2}
    tl = JSMath.hypot(tx, ty, tz)
    {tx, ty, tz} = {tx / tl, ty / tl, tz / tl}
    {ax, ay} = {ty, -tx}
    al = JSMath.hypot(ax, ay)
    {ax, ay} = {ax / al, ay / al}
    {bx, by, bz} = {-tz * ay, tz * ax, tx * ay - ty * ax}

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

  defp extent(pt, cs, ss, ct, st, acc) do
    0
    |> steps(7, &(&1 < @nu * @nv))
    |> Enum.reduce(acc, fn k, {mx, my} ->
      {px, py, pz, _, _, _} = elem(pt, k)
      x = cs * px - ss * py
      y = ct * (ss * px + cs * py) - st * pz
      z = st * (ss * px + cs * py) + ct * pz
      {max(mx, abs(x) / (@d - z)), max(my, abs(y) / (@d - z))}
    end)
  end

  def frame(state, t, env) do
    s = t * 0.3
    tt = 0.48 - 0.28 * :math.cos(t * 0.35)
    {cs, ss, ct, st} = {:math.cos(s), :math.sin(s), :math.cos(tt), :math.sin(tt)}
    rot = {cs, -ss, ct * ss, ct * cs, -st, st * ss, st * cs, ct}

    buf =
      Enum.reduce(0..(@nu * @nv - 1), %{}, fn k, buf ->
        plot(buf, elem(state.points, k), k, rot, state, env.paper)
      end)

    cells = for q <- 0..(@cols * @rows - 1), not cut?(buf, q), into: %{}, do: {q, buf[q]}
    kept = drop_scraps(cells)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: kept |> Map.get(c + r * @cols, {0, 0, " "}) |> elem(2)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp plot(buf, {px, py, pz, nx, ny, nz}, k, rot, state, paper) do
    {r00, r01, r10, r11, r12, r20, r21, r22} = rot
    wz = r20 * nx + r21 * ny + r22 * nz
    x = r00 * px + r01 * py
    y = r10 * px + r11 * py + r12 * pz
    z = r20 * px + r21 * py + r22 * pz
    ooz = 1 / (@d - z)
    col = floor(@cols / 2 + state.k * ooz * x)
    row = floor(@rows / 2 - state.k * @aspect * ooz * y)
    q = col + row * @cols

    cond do
      wz < -0.15 ->
        buf

      col < 0 or col >= @cols or row < 0 or row >= @rows ->
        buf

      match?(%{^q => {d, _, _}} when z + 20 <= d, buf) ->
        buf

      true ->
        Map.put(
          buf,
          q,
          {JSMath.fround(z + 20), div(k, @nv), glyph(nx, ny, nz, wz, rot, state, paper)}
        )
    end
  end

  defp glyph(nx, ny, nz, wz, {r00, r01, r10, r11, r12, _, _, _}, state, paper) do
    wx = r00 * nx + r01 * ny
    wy = r10 * nx + r11 * ny + r12 * nz
    {lx, ly, lz} = state.light
    {hx, hy, hz} = state.half
    diff = max(0, wx * lx + wy * ly + wz * lz)
    spec = :math.pow(max(0, wx * hx + wy * hy + wz * hz), 24)
    i = JSMath.round(min(1, 0.08 + diff * 0.8 + spec * 0.5) * 8)
    elem(@ramp, if(paper, do: 8 - i, else: i))
  end

  # Where one strand passes over another, clear the lower strand's cell beside it.
  defp cut?(buf, q) do
    c = rem(q, @cols)

    case buf do
      %{^q => {d, along, _}} ->
        (c > 0 and over?(buf, q - 1, d, along)) or (c < @cols - 1 and over?(buf, q + 1, d, along)) or
          (q >= @cols and over?(buf, q - @cols, d, along)) or
          (q < @cols * @rows - @cols and over?(buf, q + @cols, d, along))

      _ ->
        true
    end
  end

  defp over?(buf, p, d, along) do
    case buf do
      %{^p => {dp, ap, _}} ->
        s = abs(ap - along)
        dp > d + @tube * 0.9 and min(s, @nu - s) > @nu / 16

      _ ->
        false
    end
  end

  # Drop the small scraps a gap can leave: 4-connected pieces under 7 cells.
  defp drop_scraps(cells) do
    cells
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce({cells, MapSet.new()}, fn q, {cells, seen} ->
      if q in seen do
        {cells, seen}
      else
        part = flood([q], MapSet.new([q]), cells)
        cells = if MapSet.size(part) < 7, do: Map.drop(cells, MapSet.to_list(part)), else: cells
        {cells, MapSet.union(seen, part)}
      end
    end)
    |> elem(0)
  end

  defp flood([], part, _cells), do: part

  defp flood([p | stack], part, cells) do
    c = rem(p, @cols)

    near = [
      if(c > 0, do: p - 1, else: -1),
      if(c < @cols - 1, do: p + 1, else: -1),
      p - @cols,
      p + @cols
    ]

    next = for o <- near, o >= 0, Map.has_key?(cells, o), o not in part, do: o
    flood(next ++ stack, Enum.reduce(next, part, &MapSet.put(&2, &1)), cells)
  end
end

defmodule Ascii.Pieces.TorusKnotTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.TorusKnot
  use Ascii.GoldenCase, slug: "torus-knot", piece: Ascii.Pieces.TorusKnot

  alias Ascii.Pieces.TorusKnot
  alias Ascii.Pieces.TorusKnotTest.Upstream

  # The port plots into a scratch depth buffer of float32 bits, shades only
  # the point that keeps each cell, and brackets Math.pow before taking it
  # exactly. Upstream below, plainly, shades every point as it is written.

  setup_all do
    %{piece: TorusKnot.init(TorusKnot.meta().options), upstream: Upstream.init(%{})}
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

  # At 209/30 s a point lands in a cell whose stored float32 depth rounded
  # down below an earlier point's, and beats it by less than a float32 step:
  # it wins only because the comparison is with the stored, rounded value.
  test "a point just above a rounded-down float32 depth wins, as upstream's does", context do
    assert_same(context, [209 / 30], false)
  end

  defp assert_same(%{piece: piece, upstream: upstream}, times, paper) do
    ours = play(TorusKnot, piece, times, paper)
    theirs = play(Upstream, upstream, times, paper)

    for {t, a, b} <- Enum.zip([times, ours, theirs]) do
      assert a == b, "t = #{t}, paper: #{paper}\n\nport:\n#{a}\n\nupstream:\n#{b}"
    end
  end

  # Each a fresh instance, threading its state through the times in turn.
  defp play(mod, state, times, paper) do
    env = %Ascii.Env{cols: 60, rows: 28, paper: paper}

    {frames, _} =
      Enum.map_reduce(times, state, fn t, state ->
        {io, nil, state} = mod.frame(state, t * 1.0, env)
        {IO.iodata_to_binary(io), state}
      end)

    frames
  end
end
