defmodule Ascii.Pieces.Lighthouse do
  @moduledoc """
  A beam sweeping over night sea from a lighthouse on rocks.

  A banded lighthouse on a heap of rocks at night. Its beam turns round the
  lantern, long when it crosses the frame and a flash when it faces us,
  lighting the haze and the waves beneath; surf bursts on the rocks.

  Ported from `src/pieces/lighthouse.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Hash

  @meta %Ascii.Meta{
    name: "lighthouse",
    category: :objects,
    note: "a beam sweeping over night sea from a lighthouse on rocks",
    cols: 64,
    rows: 30,
    fps: 20
  }

  @cols 64
  @rows 30
  @n 64 * 30
  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # The tower's column, the lamp's row, the horizon's.
  @tc 32
  @lamp 5
  @horizon 19
  # Seconds a turn.
  @period 8
  # The shaft's rows; its half width at the top and the foot, in rows; rows
  # to a band, dark and light in turn.
  @top 9
  @foot 24
  @wt 2.1
  @wb 3.1
  @band 3
  # Boulders heaped round the foot, back to front, as {x, y, half width, half
  # height, waterline}: x in rows from the tower. The two behind it stand
  # clear of the sea.
  @rocks {
    {-3.9, 21.1, 2.3, 1.7, 99},
    {3.9, 20.9, 2.4, 1.8, 99},
    {-6.6, 22.9, 2.3, 1.6, 23.9},
    {6.7, 22.7, 2.2, 1.5, 23.6},
    {-1.7, 23.5, 2.7, 1.8, 24.8},
    {3.1, 23.8, 2.5, 1.7, 25.1},
    {-9.3, 24.5, 1.5, 0.9, 25},
    {9.2, 24.2, 1.3, 0.8, 24.7}
  }
  # The boulders the tower stands in front of.
  @behind 2
  # Where surf strikes: the boulder, the side it breaks on (none for foam
  # alone), and when in the swell.
  @surf [{6, -1, 0}, {7, 1, 0.45}, {3, 1, 0.8}, {2, -1, 0.3}, {4, 0, 0.62}, {5, 0, 0.15}]
  # Seconds between breakers.
  @swell 3.2
  # On paper the beam stays ink, drawn only in the light end of the ramp, a
  # pale shaft.
  @beam {{" ", ".", ":", "-", "=", "+", "*", "#"}, {" ", ".", ".", ":", ":", "-", "-", "="}}

  @impl true
  def meta, do: @meta

  defp hash(x, y), do: Hash.short(x, y)

  # Lit from the upper left.
  defp moon(u, v, nz), do: max(0, -0.5 * u - 0.45 * v + 0.75 * nz)

  @impl true
  def init(_options) do
    # The lighthouse and its rocks never move: light as 0..1 where they are
    # (stored as a Float32Array stores it), nil where they are not.
    {still, rock_at} = still()

    # Stars, a few and faint.
    stars =
      for i <- 0..23,
          c = floor(hash(i, 1) * @cols),
          r = floor(hash(i, 2) * (@horizon - 2)),
          elem(still, r * @cols + c) == nil and abs(c - @tc) > 4 do
        h = hash(i, 3)
        {r * @cols + c, if(h < 0.2, do: "*", else: if(h < 0.6, do: ".", else: "·"))}
      end

    # The surf: where each breaker strikes, at the waterline on its
    # boulder's outer flank.
    surf =
      for {{i, side, ph}, n} <- Enum.with_index(@surf) do
        {bx, _, rx, _, wl} = elem(@rocks, i)
        {@tc + 2 * (bx + rx * side * 0.95), wl - 0.2, side, ph, n}
      end

    sky =
      for r <- 0..(@horizon - 1),
          c <- 0..(@cols - 1),
          k = r * @cols + c,
          r == @lamp or elem(still, k) == nil do
        dx = (c - @tc) / 2
        dy = r + 0.5 - (@lamp + 0.5)
        {k, r, c, dx, dy, JSMath.hypot(dx, dy), elem(still, k) != nil, 0.35 * hash(c, r)}
      end

    # The sea: crests rolling in, finer toward the horizon; what of each
    # wave does not move.
    sea =
      for r <- @horizon..(@rows - 1), c <- 0..(@cols - 1) do
        d = r - @horizon + 1
        x = c / (3.2 / d + 0.6)
        dx = (c - @tc) / 2
        dy = r + 0.5 - (@lamp + 0.5)

        {r * @cols + c, c, d, JSMath.hypot(dx, dy), x * 0.9 + d * 1.7,
         :math.sin(x * 0.31 + d) * 1.5, x * 0.43 - d * 0.9, :math.exp(-(d - 1) / 6)}
      end

    solid =
      for k <- 0..(@n - 1), v = elem(still, k), v != nil do
        i = max(1, min(9, JSMath.round(v * 9)))
        {k, elem(rock_at, k), div(k, @cols) + 0.5, elem(@ramp, i), elem(@ramp, 10 - i)}
      end

    %{rock_at: rock_at, stars: stars, surf: surf, sky: sky, sea: sea, solid: solid}
  end

  defp still do
    {still, rock_at} =
      for r <- 0..(@rows - 1), c <- 0..(@cols - 1), reduce: {%{}, %{}} do
        acc -> still_cell(acc, r, c)
      end

    {List.to_tuple(for k <- 0..(@n - 1), do: Map.get(still, k)),
     List.to_tuple(for k <- 0..(@n - 1), do: Map.get(rock_at, k, -1))}
  end

  # The rocks behind the tower first, then the tower, then the rocks before it.
  defp still_cell(acc, r, c) do
    k = r * @cols + c
    x = (c - @tc) / 2
    y = r + 0.5
    acc = Enum.reduce(0..(@behind - 1), acc, &boulder(&2, &1, k, c, r, x, y))
    {still, rock_at} = acc
    {still, rock_at} = shaft(still, rock_at, k, r, x)

    still =
      case tower_top(r, c, x) do
        nil -> still
        v -> Map.put(still, k, JSMath.fround(v))
      end

    Enum.reduce(
      @behind..(tuple_size(@rocks) - 1),
      {still, rock_at},
      &boulder(&2, &1, k, c, r, x, y)
    )
  end

  defp boulder({still, rock_at} = acc, i, k, c, r, x, y) do
    {bx, by, rx, ry, wl} = elem(@rocks, i)
    u = (x - bx) / rx
    v = (y - by) / ry
    q = u * u + v * v

    if q >= 1 or y > wl + 0.5 do
      acc
    else
      nz = :math.sqrt(1 - q)
      # A dark rim on each, so heaped boulders keep apart; a little grain.
      lum =
        (0.06 + 0.86 * moon(u, v, nz)) * min(1, 0.15 + nz * 1.8) + 0.06 * (hash(c, r) - 0.5)

      {Map.put(still, k, JSMath.fround(lum)), Map.put(rock_at, k, i)}
    end
  end

  # The shaft: banded, round, a door at its foot and a slit of a light in a band.
  defp shaft(still, rock_at, k, r, x) when r >= @top and r <= @foot do
    w = @wt + (@wb - @wt) * (r - @top) / (@foot - @top)

    if abs(x) <= w do
      u = x / (w + 0.25)
      nz = :math.sqrt(1 - u * u)
      dark = rem(div(r - @top, @band), 2) == 1

      v =
        cond do
          r >= @foot - 3 and r < @foot and abs(x) < 0.6 -> 0.03
          r == @top + @band + 1 and x == 0 -> 0.03
          true -> if(dark, do: 0.24, else: 0.92) * (0.2 + 0.8 * moon(u, 0, nz))
        end

      {Map.put(still, k, JSMath.fround(v)), Map.delete(rock_at, k)}
    else
      {still, rock_at}
    end
  end

  defp shaft(still, rock_at, _k, _r, _x), do: {still, rock_at}

  # The gallery: a rail of posts, and the deck under it in shadow. The roof:
  # a dome with a vent on top, moonlit on the left. Each over the last.
  defp tower_top(r, c, x) do
    gallery = r == @top - 2 and abs(x) <= 2.9
    deck = r == @top - 1 and abs(x) <= 3
    rw = if r == @lamp - 2, do: 1.85, else: 1.15
    roof = r >= @lamp - 3 and r <= @lamp - 2 and abs(x) <= rw
    vent = r == @lamp - 4 and x == 0

    cond do
      vent ->
        0.5

      roof ->
        u = x / (rw + 0.3)
        0.12 + 0.6 * moon(u, -0.4, :math.sqrt(1 - u * u))

      deck ->
        q = x / 3.2
        0.45 * (0.25 + 0.75 * moon(x / 3.2, 0.3, :math.sqrt(1 - q * q)))

      gallery ->
        cond do
          abs(x) > 2.6 -> 0.55
          rem(c - @tc, 2) != 0 -> 0.2
          true -> 0.6 - 0.25 * (x / 3)
        end

      true ->
        nil
    end
  end

  @impl true
  def frame(state, t, env) do
    th = -0.35 + 2 * :math.pi() * t / @period
    c = :math.cos(th)
    s = :math.sin(th)
    # The lens turned square to us.
    face = if s > 0, do: :math.pow(s, 10), else: 0
    ramp = elem(@beam, if(env.paper, do: 1, else: 0))
    beam = beam(c, s)
    glare = {1.2 + 2.2 * face, 0.5 + 1.2 * face}

    {out, light} =
      Enum.reduce(state.sky, {%{}, %{}}, fn {k, r, cc, dx, dy, hd, still?, h}, {out, light} ->
        b = beam_at(dx, dy, beam) + glare(hd, glare)
        light = if r == @lamp, do: Map.put(light, cc, JSMath.fround(b)), else: light
        i = if still?, do: 0, else: min(7, floor(b * 6 + h))
        {if(i > 0, do: Map.put(out, k, elem(ramp, i)), else: out), light}
      end)

    out = Enum.reduce(state.sea, out, &sea(&1, &2, t, light, glare))
    out = Enum.reduce(state.stars, out, fn {k, ch}, out -> Map.put_new(out, k, ch) end)

    # The lighthouse and rocks over the rest, each boulder washed by the
    # swell at its own waterline; the lantern glows from within.
    swell =
      for i <- 0..(tuple_size(@rocks) - 1) do
        elem(elem(@rocks, i), 4) + 0.45 * :math.sin(2 * :math.pi() * t / @swell + i * 1.9) +
          0.25 * :math.sin(t * 1.3 + i)
      end
      |> List.to_tuple()

    out =
      Enum.reduce(state.solid, out, fn {k, rock, y, ink, pale}, out ->
        if rock >= 0 and y > elem(swell, rock),
          do: out,
          else: Map.put(out, k, if(env.paper, do: pale, else: ink))
      end)

    out = out |> lantern(face, ramp, env.paper) |> lamp(face, s)
    out = Enum.reduce(state.surf, out, &surf(&1, &2, t, state.rock_at))

    lines =
      for r <- 0..(@rows - 1) do
        for cc <- 0..(@cols - 1), do: Map.get(out, r * @cols + cc, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp glare(hd, {width, gain}) do
    q = hd / width
    :math.exp(-(q * q)) * gain
  end

  # The beam in the haze through a cell: a cone seen side on, so the more it
  # turns toward or away from us the shorter, wider and brighter it looks.
  defp beam(c, s) do
    fore = max(abs(c), 0.1)
    ax = if JSMath.sign(c) == 0, do: 1, else: JSMath.sign(c)
    ay = min(0.35, 0.02 / fore)

    %{
      ax: ax,
      ay: ay,
      m: JSMath.hypot(ax, ay),
      spread: 0.11 / fore,
      reach: 22 * fore,
      gain: min(1.6, 1 / :math.pow(fore, 0.3)),
      side: if(s < 0, do: 0.75, else: 1)
    }
  end

  defp beam_at(dx, dy, %{ax: ax, ay: ay, m: m} = beam) do
    a = (dx * ax + dy * ay) / m

    if a <= 0 do
      0
    else
      across = abs(dx * ay - dy * ax) / m
      half = 0.5 + a * beam.spread
      q = across / half
      # Past six the first factor is below the smallest double: zero.
      if q > 6,
        do: 0,
        else: :math.exp(-:math.pow(q, 4)) * :math.exp(-a / beam.reach) * beam.gain * beam.side
    end
  end

  # The sea: crests rolling in, finer toward the horizon, lit under the beam.
  defp sea({k, cc, d, hd, a, b, e, fade}, out, t, light, glare) do
    wave = :math.sin(a - t * 2.2 + b) + 0.6 * :math.sin(e + t * 1.3)
    lit = min(1, Map.fetch!(light, cc) * 0.9 + glare(hd, glare) * 0.5) * fade

    cond do
      wave > 0.9 - 0.5 * lit ->
        Map.put(
          out,
          k,
          cond do
            lit > 0.5 -> "="
            lit > 0.2 -> "~"
            d < 3 -> "-"
            true -> "~"
          end
        )

      wave > 0.4 - 0.4 * lit and (d < 3 or lit > 0.15) ->
        Map.put(out, k, if(d < 3, do: ".", else: "-"))

      d == 1 ->
        Map.put(out, k, "_")

      true ->
        out
    end
  end

  defp lantern(out, face, ramp, paper) do
    glow = 0.75 + 0.25 * face

    for r <- (@lamp - 1)..(@lamp + 1), x <- -3..3, reduce: out do
      out ->
        edge = abs(x) == 3
        bar = abs(x) == 2

        v =
          cond do
            edge -> 0.34
            bar -> 0.2
            true -> glow * (1 - 0.1 * abs(x)) * if(r == @lamp, do: 1, else: 0.85)
          end

        i = max(1, min(9, JSMath.round(v * 9)))

        # On paper the glass, being light, keeps to the pale end like the beam.
        ch =
          cond do
            paper and not edge and not bar -> elem(ramp, min(7, JSMath.round(v * 7)))
            paper -> elem(@ramp, 10 - i)
            true -> elem(@ramp, i)
          end

        Map.put(out, r * @cols + @tc + x, ch)
    end
  end

  # The lamp, and the rays when it faces us.
  defp lamp(out, face, s) do
    l = @lamp * @cols + @tc

    ch =
      cond do
        face > 0.3 -> "@"
        s > -0.2 -> "*"
        true -> "o"
      end

    out = Map.put(out, l, ch)

    if face > 0.5 do
      out
      |> Map.put(l - @cols, "|")
      |> Map.put(l + @cols, "|")
      |> Map.put(l - 1, "=")
      |> Map.put(l + 1, "=")
    else
      out
    end
  end

  # Surf: a breaker bursts on a boulder, its spray thrown up in a fan that
  # falls back as drops.
  defp surf({x0, y0, side, ph, n}, out, t, rock_at) do
    u = JSMath.mod(JSMath.mod(t / @swell + ph, 1) + 1, 1)
    tt = u * @swell

    if tt > 1.6 do
      out
    else
      # Foam spreading along the waterline where it broke.
      fr = floor(y0 + 0.7)

      out =
        Enum.reduce(-4..4, out, fn j, out ->
          cx = JSMath.round(x0) + j

          if tt < 1.3 and abs(j) <= 1 + tt * 3 and cx >= 0 and cx < @cols and fr < @rows,
            do: Map.put(out, fr * @cols + cx, if(tt < 0.5 and abs(j) < 2, do: "=", else: "~")),
            else: out
        end)

      if side == 0, do: out, else: spray(out, x0, y0, side, n, tt, rock_at)
    end
  end

  # The spray, a fan of drops thrown up and out off the rock, thick at first,
  # falling back as it thins.
  defp spray(out, x0, y0, side, n, tt, rock_at) do
    for j <- 0..17, reduce: out do
      out ->
        f = j / 17
        h1 = hash(j, n + 7)
        h2 = hash(j, n + 19)
        vx = side * (1 + 13 * f * f) + (h1 - 0.5) * 3
        vy = (11 - 6 * f) * (0.8 + 0.4 * h2)
        up = vy - 18 * tt > 0

        Enum.reduce(0..if(up, do: 1, else: 0), out, fn back, out ->
          drop(out, {x0, y0, vx, vy}, tt, back, {f, up}, rock_at)
        end)
    end
  end

  defp drop(out, {x0, y0, vx, vy}, tt, back, {f, up}, rock_at) do
    ts = tt - back * 0.06
    cx = JSMath.round(x0 + vx * ts)
    cy = JSMath.round(y0 - vy * ts + 9 * ts * ts)

    cond do
      ts < 0 or cy < 0 or cy >= @rows or cx < 0 or cx >= @cols or cy > y0 + 0.3 ->
        out

      elem(rock_at, cy * @cols + cx) >= 0 and tt > 0.2 ->
        out

      back == 1 ->
        k = cy * @cols + cx
        if Map.get(out, k, " ") in [" ", "~"], do: Map.put(out, k, "'"), else: out

      true ->
        ch =
          cond do
            tt < 0.22 -> if f < 0.4, do: "#", else: "*"
            up -> "*"
            tt < 1.15 -> ":"
            true -> "."
          end

        Map.put(out, cy * @cols + cx, ch)
    end
  end
end
