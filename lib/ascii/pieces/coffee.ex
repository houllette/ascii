defmodule Ascii.Pieces.Coffee do
  @moduledoc """
  Steam curling up from a cup of coffee on its saucer.

  A cup of coffee on its saucer, lit from the upper left, with a few thin
  wisps of steam lifting off the surface and curling as they climb.

  The cup and saucer are a still picture, traced once in `init/1` on a grid
  of two looks across and four down to a cell; each frame only draws the
  steam over it.

  Ported from `src/pieces/coffee.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "coffee",
    category: :objects,
    note: "steam curling up from a cup of coffee on its saucer",
    cols: 52,
    rows: 24,
    fps: 20,
    loop: 6
  }

  @cols 52
  @rows 24
  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # How steeply we look down at the table.
  @tilt 0.34
  # The cup's height and its radius at the rim, in rows; the coffee's level.
  @h 7.6
  @rt 6.2
  @hc 7.6 - 0.55
  # Seconds before the steam repeats.
  @period 6
  # Wisps: x and z where they leave the coffee, height in rows, phase, lean.
  @wisps [
    {-2.4, 0.6, 11, 0, -0.12},
    {0.3, -1.4, 14, 2.2, 0.05},
    {2.9, 0.5, 10, 4.1, 0.15}
  ]
  # The saucer turned on a lathe, as {radius, height}: a flat well, rising to a rounded lip.
  @saucer [
    {0, 0},
    {4.4, 0},
    {6.5, 0.12},
    {8.7, 0.45},
    {9.9, 0.78},
    {10.4, 0.92},
    {10.6, 0.8},
    {10.55, 0.55},
    {10.2, 0.4}
  ]
  # The handle: a thin loop on the right, standing out from the wall at z = 0.
  @hy 4.1
  @ax 3.9
  @ay 2.6
  @tube 0.42

  # Looks per cell, across and down.
  @sx 2
  @sy 4
  @w 52 * 2
  @hh 24 * 4
  @n 52 * 24
  @cs :math.sqrt(1 - 0.34 * 0.34)
  @sn @tilt
  # The saucer's centre, a little left so the handle fits.
  @cx 52 / 2 - 1.5
  @base 24 - 4.4
  @two_pi 2 * :math.pi()

  # Parts of the picture.
  @saucer_part 1
  @cup 2
  @lip 3
  @coffee 4

  @impl true
  def meta, do: @meta

  defp cup_r(h), do: @rt * (0.62 + 0.38 * :math.sin(:math.pi() / 2 * min(1, max(0, h) / @h)))

  defp smooth(a, b, x) do
    u = min(1, max(0, (x - a) / (b - a)))
    u * u * (3 - 2 * u)
  end

  defp norm(x, y, z) do
    m = JSMath.hypot(x, y, z)
    {x / m, y / m, z / m}
  end

  defp dot({a, b, c}, {x, y, z}), do: a * x + b * y + c * z

  defp to_cell(x, y, z), do: {@cx + 2 * x, @base - (y * @cs - z * @sn)}

  # A glaze's glint, where the light bounces toward us.
  defp glint(n, p, hv) do
    k = dot(n, hv)
    if k > 0, do: :math.pow(k, p), else: 0
  end

  @impl true
  def init(_options) do
    l = norm(-0.62, 0.62, 0.48)
    {l0, l1, l2} = l
    hv = norm(l0, l1 + @sn, l2 + @cs)
    light = %{l: l, hv: hv}

    buf =
      %{}
      |> saucer(light)
      |> cup(light)
      |> lip(light)
      |> coffee(light)

    {still, kind} = cells(buf)
    still = foot(still, kind)
    still = handle(still, kind, light)
    top = floor(elem(to_cell(0, @hc, 0), 1))
    w0 = for {x, z, _, _, _} <- @wisps, do: to_cell(x, @hc, z)

    %{
      base: {base(still, false), base(still, true)},
      still: still,
      top: top,
      w0: w0
    }
  end

  # Draws a look at x, y, z if nothing nearer holds its sub-cell; its light
  # is only worked out then.
  defp plot(buf, x, y, z, part, lum) do
    {c, r} = to_cell(x, y, z)
    px = floor(c * @sx)
    py = floor(r * @sy)

    if px < 0 or px >= @w or py < 0 or py >= @hh do
      buf
    else
      k = py * @w + px
      d = z * @cs + y * @sn

      case buf do
        %{^k => {near, _, _}} when d <= near -> buf
        _ -> Map.put(buf, k, {JSMath.fround(d), part, JSMath.fround(lum.())})
      end
    end
  end

  defp lit(n, albedo, extra, l), do: albedo * (0.1 + 0.9 * max(0, dot(n, l))) + extra

  # The saucer: lit more on the left as it turns from the light, shaded by
  # the cup and darkened close round its foot.
  defp saucer(buf, light) do
    foot = cup_r(0)

    @saucer
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(buf, fn [{r1, y1}, {r2, y2}], buf ->
      len = JSMath.hypot(r2 - r1, y2 - y1)
      nr = -(y2 - y1) / len
      ny = (r2 - r1) / len

      Stream.iterate(0, &(&1 + 0.04 / len))
      |> Stream.take_while(&(&1 <= 1))
      |> Enum.reduce(buf, fn f, buf ->
        p = r1 + (r2 - r1) * f
        y = y1 + (y2 - y1) * f
        ring = %{p: p, y: y, nr: nr, ny: ny, foot: foot, shade: shade_steps(y, light.l)}
        saucer_ring(buf, 0, ring, light)
      end)
    end)
  end

  defp saucer_ring(buf, a, ring, light) when a < @two_pi do
    %{p: p, y: y, nr: nr, ny: ny, foot: foot} = ring
    ca = :math.cos(a)
    sa = :math.sin(a)
    x = p * ca
    z = p * sa

    buf =
      plot(buf, x, y, z, @saucer_part, fn ->
        n = norm(nr * ca, ny, nr * sa)
        side = 0.78 - 0.22 * (x / 10.6)
        ao = 0.35 + 0.65 * smooth(foot - 0.1, foot + 1.4, p)
        albedo = 0.78 * side * ao * if(shadowed?(x, z, ring.shade), do: 0.35, else: 1)
        lit(n, albedo, 0.25 * glint(n, 12, light.hv), light.l)
      end)

    saucer_ring(buf, a + 0.09 / max(p, 0.5), ring, light)
  end

  defp saucer_ring(buf, _a, _ring, _light), do: buf

  # The steps toward the light from a ring at height y, while below the
  # rim: the offsets along the way and the cup's radius there (nil below the
  # table).
  defp shade_steps(y, {l0, l1, l2}) do
    Stream.iterate(0.3, &(&1 + 0.25))
    |> Stream.take_while(&(&1 < 16))
    |> Enum.reduce_while([], fn s, acc ->
      yy = y + l1 * s

      if yy > @h,
        do: {:halt, acc},
        else: {:cont, [{l0 * s, l2 * s, if(yy > 0, do: cup_r(yy))} | acc]}
    end)
    |> Enum.reverse()
  end

  # Is the cup in the way between this point and the light? The squared
  # distance settles all but the closest calls, which take Math.hypot.
  defp shadowed?(x, z, steps) do
    Enum.any?(steps, fn
      {_, _, nil} ->
        false

      {ox, oz, r} ->
        a = x + ox
        b = z + oz
        q = a * a + b * b
        rr = r * r

        cond do
          q < rr * 0.999999 -> true
          q > rr * 1.000001 -> false
          true -> JSMath.hypot(a, b) < r
        end
    end)
  end

  # The cup, outside and in.
  defp cup(buf, light) do
    Stream.iterate(0, &(&1 + 0.05))
    |> Stream.take_while(&(&1 <= @h))
    |> Enum.reduce(buf, fn h, buf ->
      r = cup_r(h)
      dr = (cup_r(h + 0.05) - cup_r(h - 0.05)) / 0.1
      cup_ring(buf, 0, h, r, dr, light)
    end)
  end

  defp cup_ring(buf, a, h, r, dr, light) when a < @two_pi do
    ca = :math.cos(a)
    sa = :math.sin(a)

    buf =
      if sa > -0.3 do
        plot(buf, r * ca, h, r * sa, @cup, fn ->
          n = norm(ca, -dr, sa)
          lit(n, 0.95, 0.35 * glint(n, 10, light.hv), light.l)
        end)
      else
        buf
      end

    buf =
      if h > @hc and sa < 0.3 do
        plot(buf, (r - 0.4) * ca, h, (r - 0.4) * sa, @cup, fn ->
          lit(norm(-ca, dr, -sa), 0.75, 0, light.l)
        end)
      else
        buf
      end

    cup_ring(buf, a + 0.1 / r, h, r, dr, light)
  end

  defp cup_ring(buf, _a, _h, _r, _dr, _light), do: buf

  # The lip, lit as one rounded edge facing out and up: bright on the left,
  # falling off to the right.
  defp lip(buf, %{l: l}) do
    rim = cup_r(@h)

    Stream.iterate(0, &(&1 + 0.12))
    |> Stream.take_while(&(&1 <= :math.pi()))
    |> Enum.reduce(buf, fn v, buf ->
      p = rim - 0.2 - 0.2 * :math.cos(v)
      y = @h + 0.12 * :math.sin(v)
      lip_ring(buf, 0, rim, p, y, l)
    end)
  end

  defp lip_ring(buf, a, rim, p, y, l) when a < @two_pi do
    ca = :math.cos(a)
    sa = :math.sin(a)

    buf =
      plot(buf, p * ca, y, p * sa, @lip, fn ->
        lit(norm(0.6 * ca, 0.8, 0.6 * sa), 0.95, 0.12, l)
      end)

    lip_ring(buf, a + 0.06 / rim, rim, p, y, l)
  end

  defp lip_ring(buf, _a, _rim, _p, _y, _l), do: buf

  # The coffee: a dark pool, a paler ring of crema at the wall, one glint of
  # the light.
  defp coffee(buf, light) do
    rc = cup_r(@hc) - 0.4

    Stream.iterate(0, &(&1 + 0.08))
    |> Stream.take_while(&(&1 < rc))
    |> Enum.reduce(buf, fn p, buf -> coffee_ring(buf, 0, p, rc, light) end)
  end

  defp coffee_ring(buf, a, p, rc, light) when a < @two_pi do
    x = p * :math.cos(a)
    z = p * :math.sin(a)

    buf =
      plot(buf, x, @hc, z, @coffee, fn ->
        u = (x + 2.4) / 1.1
        v = (z + 1.4) / 0.8
        shine = :math.exp(-(u * u + v * v))
        lit({0, 1, 0}, 0.04 + 0.16 * smooth(0.82 * rc, rc, p), 0.85 * shine, light.l)
      end)

    coffee_ring(buf, a + 0.08 / max(p, 0.5), p, rc, light)
  end

  defp coffee_ring(buf, _a, _p, _rc, _light), do: buf

  # Down to cells: the lip wins any cell it is in, so it reads as one line;
  # elsewhere the mean light where most looks land, and a soft edge where a
  # few do.
  defp cells(buf) do
    {still, kind} =
      for k <- 0..(@n - 1) do
        c = rem(k, @cols)
        r = div(k, @cols)

        {n, sum, low, lip, lip_sum, owner} =
          for j <- 0..(@sy - 1), i <- 0..(@sx - 1), reduce: {0, 0, 0, 0, 0, 0} do
            acc -> look(Map.get(buf, (r * @sy + j) * @w + c * @sx + i), j, acc)
          end

        still =
          cond do
            lip >= 2 -> min(1, lip_sum / lip)
            n == 0 -> nil
            n < 3 -> if low * 2 > n, do: "_", else: "'"
            true -> min(1, sum / n)
          end

        {still, owner}
      end
      |> Enum.unzip()

    {List.to_tuple(still), List.to_tuple(kind)}
  end

  defp look(nil, _j, acc), do: acc
  defp look({_d, _part, v}, _j, acc) when v < 0, do: acc

  defp look({_d, part, v}, j, {n, sum, low, lip, lip_sum, owner}) do
    low = if j >= @sy / 2, do: low + 1, else: low
    {lip, lip_sum} = if part == @lip, do: {lip + 1, lip_sum + v}, else: {lip, lip_sum}
    {n + 1, sum + v, low, lip, lip_sum, max(owner, if(part == @saucer_part, do: 1, else: 2))}
  end

  # One thin dark line where the cup stands in front of the saucer, darkest
  # under its foot.
  defp foot(still, kind) do
    {_, foot} = to_cell(0, 0, 0)

    Enum.reduce(@cols..(@n - 2)//1, still, fn k, still ->
      v = elem(still, k)

      cond do
        elem(kind, k) != 1 or not is_number(v) ->
          still

        elem(kind, k - @cols) == 2 and k / @cols > foot - 0.5 ->
          put_elem(still, k, min(v, 0.06))

        elem(kind, k - 1) == 2 or elem(kind, k + 1) == 2 ->
          put_elem(still, k, v * 0.4)

        true ->
          still
      end
    end)
  end

  # The handle, a cell thick: each cell near its line lit by the tube's own
  # normal there. Through its loop the saucer is in shade, so the hole reads
  # open.
  defp handle(still, kind, light) do
    x0 = cup_r(@hy) - 1.3

    ring =
      Stream.iterate(-2.1, &(&1 + 0.02))
      |> Stream.take_while(&(&1 <= 2.1))
      |> Enum.map(&{x0 + @ax * :math.cos(&1), @hy + @ay * :math.sin(&1)})

    Enum.reduce(0..(@n - 1), still, fn k, still ->
      c = rem(k, @cols)
      r = div(k, @cols)
      x = (c + 0.5 - @cx) / 2
      y = (@base - (r + 0.5)) / @cs

      if x < cup_r(y) - 0.1 or x > x0 + @ax + 1,
        do: still,
        else: handle_cell(still, kind, k, x, y, x0, ring, light)
    end)
  end

  defp handle_cell(still, kind, k, x, y, x0, ring, light) do
    {best, ox, oy} =
      Enum.reduce(ring, {9, 0, 0}, fn {lx, ly}, {best, _, _} = acc ->
        d = JSMath.hypot(x - lx, y - ly)
        if d < best, do: {d, (x - lx) / @tube, (y - ly) / @tube}, else: acc
      end)

    cond do
      best < @tube + 0.12 ->
        n = norm(ox, oy, :math.sqrt(max(0.05, 1 - ox * ox - oy * oy)))

        put_elem(
          still,
          k,
          min(1, 0.1 + 0.85 * max(0, dot(n, light.l)) + 0.3 * glint(n, 10, light.hv))
        )

      (x - x0) * (x - x0) / (@ax * @ax) + (y - @hy) * (y - @hy) / (@ay * @ay) < 1 and
          elem(kind, k) != 2 ->
        put_elem(still, k, nil)

      true ->
        still
    end
  end

  defp base(still, paper) do
    still
    |> Tuple.to_list()
    |> Enum.map(fn
      nil -> " "
      v when is_binary(v) -> v
      v -> elem(@ramp, max(1, JSMath.round(if(paper, do: 1 - v, else: v) * 9)))
    end)
    |> List.to_tuple()
  end

  @impl true
  def frame(state, t, env) do
    out = elem(state.base, if(env.paper, do: 1, else: 0))

    over =
      @wisps
      |> Enum.zip(state.w0)
      |> Enum.reduce(%{}, fn {wisp, w0}, over -> wisp(over, wisp, w0, t, state) end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          k = r * @cols + c
          Map.get(over, k, elem(out, k))
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp wisp(over, {_, _, len, _, _} = wisp, {w0x, w0y}, t, state) do
    Enum.reduce_while(floor(w0y - 0.5)..0//-1, over, fn r, over ->
      s = w0y - (r + 0.5)

      if s > len,
        do: {:halt, over},
        else: {:cont, wisp_row(over, wisp, w0x, r, s, t, state)}
    end)
  end

  # Where a wisp is at height s rows: a bend that rides up it and grows as
  # it climbs. Below the surface upstream's power gives NaN: nil here.
  defp col_at({_, _, len, ph, lean}, w0x, s, t) do
    f = s / len
    w = 2 * :math.pi() * t / @period

    if f >= 0 do
      w0x +
        2 *
          (lean * s + (0.2 + 1.7 * :math.pow(f, 1.5)) * :math.sin(0.75 * s - 2 * w + ph) +
             0.3 * f * :math.sin(w + ph))
    end
  end

  defp free?(still, k, r, top) do
    case elem(still, k) do
      nil -> true
      v when is_number(v) -> r >= top and v < 0.3
      _ -> false
    end
  end

  defp wisp_row(over, {_, _, len, ph, _} = wisp, w0x, r, s, t, state) do
    c = col_at(wisp, w0x, s, t)
    cc = if c, do: floor(c)
    k = if c, do: r * @cols + cc

    if c == nil or cc < 0 or cc >= @cols or not free?(state.still, k, r, state.top) do
      over
    else
      # Faint off the surface and at the top, with breaks that rise with it.
      thin = 0.5 + 0.5 * :math.sin(0.55 * s - 2 * :math.pi() * t / @period + ph * 2)
      a = smooth(0.3, 1.8, s) * (1 - smooth(0.6 * len, len, s)) * (0.3 + 0.7 * thin)

      if a < 0.2,
        do: over,
        else: wisp_stroke(over, wisp, w0x, {r, s, t, c, cc, k, a}, state)
    end
  end

  defp wisp_stroke(over, wisp, w0x, {r, s, t, c, cc, k, a}, state) do
    up = col_at(wisp, w0x, s + 1, t)
    dn = col_at(wisp, w0x, s - 1, t)
    over = Map.put(over, k, stroke(a, c, up, dn))
    # Where it swings across faster than it climbs, it curls over: a run along the row.
    run = JSMath.round(up - c)
    n = abs(run)
    dir = JSMath.sign(run)

    if a < 0.32 or n < 2 do
      over
    else
      over = Map.put(over, k, "_")

      Enum.reduce(1..(n - 1)//1, over, fn j, over ->
        at = cc + dir * j

        if at >= 0 and at < @cols and free?(state.still, k + dir * j, r, state.top),
          do: Map.put(over, k + dir * j, curl(j, n, dir)),
          else: over
      end)
    end
  end

  defp curl(j, n, _dir) when j < n - 1, do: "_"
  defp curl(_j, _n, dir) when dir > 0, do: "/"
  defp curl(_j, _n, _dir), do: "\\"

  # Upstream's NaN below the surface fails every test: an upright stroke.
  defp stroke(a, _c, _up, _dn) when a < 0.32, do: "."
  defp stroke(_a, _c, _up, nil), do: "|"

  defp stroke(_a, c, up, dn) do
    lean = (up - dn) / 2
    bow = c - (up + dn) / 2

    cond do
      abs(lean) > 0.7 -> if lean > 0, do: "/", else: "\\"
      bow > 0.15 -> ")"
      bow < -0.15 -> "("
      true -> "|"
    end
  end
end
