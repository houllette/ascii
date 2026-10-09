defmodule Ascii.Pieces.HeartTest.Upstream do
  @moduledoc false
  # A plain port of upstream's heart.ts, line for line: every ray marched
  # with the field's Math.cbrt at every step, and shaded with Math.cbrt,
  # Math.hypot and Math.pow. No fast paths, no margins.

  alias Ascii.JSMath

  @cols 52
  @rows 24
  @ramp {".", ",", "-", "~", ":", ";", "=", "+", "*", "#", "%", "@"}
  # Cells per unit across.
  @k 18
  @cx @cols / 2
  @cy @rows / 2 + 1.3

  def init(_options) do
    m = JSMath.hypot(-0.4, -1, 0.65)
    # Upper left, in front (front is -y).
    light = {-0.4 / m, -1 / m, 0.65 / m}
    steps = 0.04 |> Stream.iterate(&(&1 + 0.04)) |> Enum.take_while(&(&1 <= 3.2))
    %{light: light, steps: steps}
  end

  # The same surface with the cube root taken, which keeps the gradient sane
  # along the waist. Inside is negative; z is up and y is the thin axis.
  defp field(x, y, z),
    do: x * x + 2.25 * y * y + z * z - 1 - z * JSMath.cbrt(x * x + 0.1125 * y * y)

  def frame(state, t, env) do
    # Lub, then a softer dub, once a second.
    p = JSMath.mod(t, 1)
    e1 = (p - 0.1) / 0.055
    e2 = (p - 0.32) / 0.06
    s = 1 + 0.075 * :math.exp(-(e1 * e1)) + 0.045 * :math.exp(-(e2 * e2))
    yaw = 0.62 * :math.sin(t / 8 * :math.pi() * 2)
    tilt = 0.18
    rot = {:math.cos(yaw), :math.sin(yaw), :math.cos(tilt), :math.sin(tilt)}
    # Light and eye moved into the heart's own frame.
    {lx, ly, lz} = state.light
    {lx, ly, lz} = light = to_obj(rot, lx, ly, lz)
    {dx, dy, dz} = dir = to_obj(rot, 0.0, 1.0, 0.0)
    hx = lx - dx
    hy = ly - dy
    hz = lz - dz
    hm = JSMath.hypot(hx, hy, hz)
    half = {hx / hm, hy / hm, hz / hm}

    lines =
      for r <- 0..(@rows - 1) do
        v = (@cy - r - 0.5) * 2 / @k / s

        for c <- 0..(@cols - 1) do
          u = (c + 0.5 - @cx) / @k / s

          if v < -1.15 or v > 1.4 or u < -1.3 or u > 1.3,
            do: " ",
            else: pixel(rot, dir, light, half, state.steps, env.paper, u, v)
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # March the ray (u, d, v) from in front; ox + d * dx is the point in object space.
  defp pixel(rot, {dx, dy, dz} = dir, light, half, steps, paper, u, v) do
    {ox, oy, oz} = to_obj(rot, u, -1.6, v)

    case march(steps, 0, {ox, oy, oz}, dir) do
      nil ->
        " "

      hit ->
        i = shade(ox + hit * dx, oy + hit * dy, oz + hit * dz, light, half)
        elem(@ramp, if(paper, do: tuple_size(@ramp) - 1 - i, else: i))
    end
  end

  defp to_obj({cyw, syw, ct, st}, x, y, z) do
    y1 = ct * y - st * z
    z1 = st * y + ct * z
    {cyw * x + syw * y1, -syw * x + cyw * y1, z1}
  end

  defp inside?({ox, oy, oz}, {dx, dy, dz}, d),
    do: field(ox + d * dx, oy + d * dy, oz + d * dz) < 0

  defp march([], _d0, _o, _dir), do: nil

  defp march([d | rest], d0, o, dir) do
    if inside?(o, dir, d), do: bisect(d0, d, o, dir, 10), else: march(rest, d, o, dir)
  end

  defp bisect(_a, b, _o, _dir, 0), do: b

  defp bisect(a, b, o, dir, n) do
    mid = (a + b) / 2

    if inside?(o, dir, mid),
      do: bisect(a, mid, o, dir, n - 1),
      else: bisect(mid, b, o, dir, n - 1)
  end

  defp shade(x, y, z, {lx, ly, lz}, {hx, hy, hz}) do
    q = x * x + 0.1125 * y * y + 1.0e-9
    w = z / (3 * JSMath.cbrt(q * q))
    nx = 2 * x - w * 2 * x
    ny = 4.5 * y - w * 0.225 * y
    nz = 2 * z - JSMath.cbrt(q)
    nm = JSMath.hypot(nx, ny, nz)
    nm = if nm == 0, do: 1, else: nm
    nx = nx / nm
    ny = ny / nm
    nz = nz / nm
    diff = max(0, nx * lx + ny * ly + nz * lz)
    spec = :math.pow(max(0, nx * hx + ny * hy + nz * hz), 40)
    b = min(1, 0.1 + 0.62 * diff + 0.4 * spec)
    JSMath.round(b * (tuple_size(@ramp) - 1))
  end
end

defmodule Ascii.Pieces.HeartTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Heart
  use Ascii.GoldenCase, slug: "heart", piece: Ascii.Pieces.Heart

  alias Ascii.Pieces.Heart
  alias Ascii.Pieces.HeartTest.Upstream

  # The port decides the field's sign by comparing cubes, taking Math.cbrt
  # only within a margin, and brackets Math.pow before taking it exactly.
  # Upstream below, plainly, takes Math.cbrt at every step. No frame in
  # 6,601 tried (every 1/30 s to 120 s, and 3,000 random times to 1,000 s)
  # needs either exact fallback, so there is no fixed time to pin here.

  setup_all do
    %{piece: Heart.init(Heart.meta().options), upstream: Upstream.init(%{})}
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
    ours = play(Heart, piece, times, paper)
    theirs = play(Upstream, upstream, times, paper)

    for {t, a, b} <- Enum.zip([times, ours, theirs]) do
      assert a == b, "t = #{t}, paper: #{paper}\n\nport:\n#{a}\n\nupstream:\n#{b}"
    end
  end

  # Each a fresh instance, threading its state through the times in turn.
  defp play(mod, state, times, paper) do
    env = %Ascii.Env{cols: 52, rows: 24, paper: paper}

    {frames, _} =
      Enum.map_reduce(times, state, fn t, state ->
        {io, nil, state} = mod.frame(state, t * 1.0, env)
        {IO.iodata_to_binary(io), state}
      end)

    frames
  end
end
