defmodule AsciiArt.Pieces.Heart do
  @moduledoc """
  A glossy 3d heart swaying and beating lub-dub.

  The implicit heart surface (x² + 9/4 y² + z² - 1)³ = x²z³ + 9/80 y²z³,
  ray-marched per cell, swaying from side to side and beating lub-dub.

  Ported from `src/pieces/heart.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "heart",
    category: :shapes,
    note: "a glossy 3d heart swaying and beating lub-dub",
    cols: 52,
    rows: 24,
    fps: 30,
    loop: 8
  }

  @cols 52
  @rows 24
  @ramp {".", ",", "-", "~", ":", ";", "=", "+", "*", "#", "%", "@"}
  # Cells per unit across.
  @k 18
  @cx @cols / 2
  @cy @rows / 2 + 1.3

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    m = JSMath.hypot(-0.4, -1, 0.65)
    # Upper left, in front (front is -y).
    light = {-0.4 / m, -1 / m, 0.65 / m}
    steps = 0.04 |> Stream.iterate(&(&1 + 0.04)) |> Enum.take_while(&(&1 <= 3.2))
    %{light: light, steps: steps}
  end

  # The same surface with the cube root taken, which keeps the gradient sane
  # along the waist. Inside is negative; z is up and y is the thin axis:
  #
  #     x * x + 2.25 * y * y + z * z - 1 - z * Math.cbrt(x * x + 0.1125 * y * y)
  #
  # Only its sign is used. Written a - z * c, that is negative exactly when
  # a < fl(z * c), and the signs of a and z settle most points outright. The
  # rest compare a³ with z³ q instead of taking the cube root: the cube root
  # is within a part in 10^15, so a margin of a part in 10^12 settles all but
  # points on the surface itself, which take Math.cbrt as upstream does.
  @margin 1.0e-12
  @tiny 1.0e-280

  @compile {:inline, inside?: 3}
  defp inside?(x, y, z) do
    xx = x * x
    a = xx + 2.25 * y * y + z * z - 1.0

    cond do
      z > 0.0 and a < 0.0 -> true
      z > 0.0 -> compare(a, z, xx + 0.1125 * y * y) == :lt
      # Both negative: a < z * c when -a > -z * c, and negation is exact.
      z < 0.0 and a < 0.0 -> compare(-a, -z, xx + 0.1125 * y * y) == :gt
      true -> a < 0.0
    end
  end

  # a against fl(z * Math.cbrt(q)), for a and z not negative.
  defp compare(a, z, q) do
    lhs = a * a * a
    rhs = z * z * z * q

    cond do
      lhs < @tiny or rhs < @tiny -> exact_compare(a, z * JSMath.cbrt(q))
      lhs < rhs * (1 - @margin) -> :lt
      lhs > rhs * (1 + @margin) -> :gt
      true -> exact_compare(a, z * JSMath.cbrt(q))
    end
  end

  defp exact_compare(a, b) when a < b, do: :lt
  defp exact_compare(a, b) when a > b, do: :gt
  defp exact_compare(_a, _b), do: :eq

  @impl true
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
    scene = {rot, dir, light, {hx / hm, hy / hm, hz / hm}, state.steps, env.paper}

    lines =
      for r <- 0..(@rows - 1) do
        v = (@cy - r - 0.5) * 2 / @k / s

        for c <- 0..(@cols - 1) do
          u = (c + 0.5 - @cx) / @k / s

          if v < -1.15 or v > 1.4 or u < -1.3 or u > 1.3,
            do: " ",
            else: pixel(scene, u, v)
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # March the ray (u, d, v) from in front; ox + d * dx is the point in object space.
  defp pixel({rot, {dx, dy, dz}, light, half, steps, paper}, u, v) do
    {ox, oy, oz} = to_obj(rot, u, -1.6, v)

    case march(steps, 0.0, ox, oy, oz, dx, dy, dz) do
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

  # The guards tell the compiler these are floats, which makes the
  # arithmetic several times faster.
  defp march([], _d0, _ox, _oy, _oz, _dx, _dy, _dz), do: nil

  defp march([d | rest], d0, ox, oy, oz, dx, dy, dz)
       when is_float(d) and is_float(ox) and is_float(oy) and is_float(oz) and is_float(dx) and
              is_float(dy) and is_float(dz) do
    if inside?(ox + d * dx, oy + d * dy, oz + d * dz),
      do: bisect(d0, d, {ox, oy, oz, dx, dy, dz}, 10),
      else: march(rest, d, ox, oy, oz, dx, dy, dz)
  end

  defp bisect(_a, b, _ray, 0), do: b

  defp bisect(a, b, {ox, oy, oz, dx, dy, dz} = ray, n)
       when is_float(a) and is_float(b) and is_float(ox) and is_float(oy) and is_float(oz) and
              is_float(dx) and is_float(dy) and is_float(dz) do
    mid = (a + b) / 2

    if inside?(ox + mid * dx, oy + mid * dy, oz + mid * dz),
      do: bisect(a, mid, ray, n - 1),
      else: bisect(mid, b, ray, n - 1)
  end

  defp shade(x, y, z, {lx, ly, lz}, {hx, hy, hz}) do
    q = x * x + 0.1125 * y * y + 1.0e-9
    w = z / (3 * JSMath.cbrt(q * q))
    nx = 2 * x - w * 2 * x
    ny = 4.5 * y - w * 0.225 * y
    nz = 2 * z - JSMath.cbrt(q)
    nm = hypot(nx, ny, nz)
    nm = if nm == 0, do: 1, else: nm
    nx = nx / nm
    ny = ny / nm
    nz = nz / nm
    diff = max(0, nx * lx + ny * ly + nz * lz)
    lit = 0.1 + 0.62 * diff
    gloss(lit, nx * hx + ny * hy + nz * hz)
  end

  # The ramp index for a highlight of max(0, dot) ** 40. That power is
  # costly, so it is bracketed first by repeated squaring (good to 1e-14);
  # the index only grows with it, so when both ends give the same index that
  # is the index, and only otherwise is Math.pow's exact value taken.
  defp gloss(lit, dot) when dot <= 0, do: level(lit, 0)

  defp gloss(lit, dot) do
    d8 = dot * dot * (dot * dot) * (dot * dot * (dot * dot))
    s40 = d8 * d8 * (d8 * d8) * d8
    lo = level(lit, max(0.0, s40 * (1 - 1.0e-12) - 1.0e-300))
    hi = level(lit, s40 * (1 + 1.0e-12) + 1.0e-300)
    if lo == hi, do: lo, else: level(lit, :math.pow(dot, 40))
  end

  defp level(lit, spec), do: JSMath.round(min(1, lit + 0.4 * spec) * (tuple_size(@ramp) - 1))

  # Math.hypot of three numbers as V8 computes it (see JSMath.hypot_list/1),
  # inline: scaled by the largest, summed with Kahan's compensation.
  defp hypot(a, b, c) do
    a = abs(a)
    b = abs(b)
    c = abs(c)

    case max(max(a, b), c) do
      m when m == 0 ->
        0.0

      m ->
        {sum, comp} = kahan(0.0, 0.0, a / m)
        {sum, comp} = kahan(sum, comp, b / m)
        {sum, _} = kahan(sum, comp, c / m)
        :math.sqrt(sum) * m
    end
  end

  defp kahan(sum, comp, n) do
    summand = n * n - comp
    pre = sum + summand
    {pre, pre - sum - summand}
  end
end
