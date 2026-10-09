defmodule Ascii.Pieces.Planet do
  @moduledoc """
  A banded ringed planet turning, with shadows both ways.

  A ringed gas giant, banded and turning, lit from the upper left. The rings
  throw a shadow across the globe and the globe one across the rings.

  Ported from `src/pieces/planet.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Rand

  @meta %Ascii.Meta{
    name: "planet",
    category: :space,
    note: "a banded ringed planet turning, with shadows both ways",
    cols: 64,
    rows: 18,
    fps: 20
  }

  @ramp {" ", ".", ",", ":", "-", "=", "+", "*", "#", "%", "@"}
  # The globe's radius, in rows.
  @rp 6.5
  # How far the ring plane opens toward the eye.
  @tilt 0.4
  # How far the axis leans in the picture.
  @roll 0.2
  # Seconds a turn.
  @day 18
  # The rings by radius, in globe radii: {from, to, opacity at from, at to,
  # brightness}. The inner one is dark dust, a dusky band where it crosses the
  # globe.
  @rings [
    {1.22, 1.48, 0.3, 0.5, 0.1},
    {1.5, 1.9, 0.85, 1, 1},
    {1.98, 2.16, 0.8, 0.65, 0.85}
  ]

  @compile {:inline, smooth: 3}

  @impl true
  def meta, do: @meta

  defp smooth(e0, e1, x) do
    u = min(1, max(0, (x - e0) / (e1 - e0)))
    u * u * (3 - 2 * u)
  end

  defp dot({a0, a1, a2}, {b0, b1, b2}), do: a0 * b0 + a1 * b1 + a2 * b2

  # Ring opacity at radius r, in globe radii, and the brightness of what is
  # there (upstream's `albedo`, which only a ring hit sets and reads).
  defp ring(r) do
    Enum.find_value(@rings, {0, nil}, fn {a, b, p, q, w} ->
      if r >= a and r < b, do: {p + (q - p) * (r - a) / (b - a), w}
    end)
  end

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    roll = {:math.cos(@roll), :math.sin(@roll)}
    v = [-0.42, 0.34, 0.84]
    [s0, s1, s2] = Enum.map(v, &(&1 / JSMath.hypot_list(v)))

    # The pole, in view space before the roll, and the equator's direction
    # toward the eye.
    space = %{
      sun: {s0, s1, s2},
      axis: {0, :math.cos(@tilt), :math.sin(@tilt)},
      e2: {0, -:math.sin(@tilt), :math.cos(@tilt)}
    }

    rand = Rand.seed(7)

    {stars, _} =
      Enum.map_reduce(1..14, rand, fn _, rand ->
        {a, rand} = Rand.next(rand)
        {b, rand} = Rand.next(rand)
        {p, rand} = Rand.next(rand)
        {{1 + JSMath.floor(a * (cols - 2)), JSMath.floor(b * rows), p * 6.283}, rand}
      end)

    cells =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          samples =
            for k <- 0..3,
                px = (c + 0.25 + 0.5 * Bitwise.band(k, 1) - cols / 2) * 0.5,
                py = rows / 2 - r - 0.25 - 0.5 * Bitwise.bsr(k, 1),
                s = sample(px, py, roll, space),
                s != nil,
                do: s

          if length(samples) < 2, do: " ", else: {samples, length(samples)}
        end
      end

    %{cells: cells, stars: stars}
  end

  # What never changes in a sample at a point on the picture, in rows: nil
  # for space, a value, or the globe's lighting and where it falls, and the
  # ring in front of it. The globe tops out below the rings, so a ring
  # crossing it reads as brighter.
  defp sample(px, py, {cr, sr}, %{sun: sun, axis: {_, a1, a2}} = space) do
    # Undo the roll.
    x = cr * px - sr * py
    y = sr * px + cr * py
    r2 = x * x + y * y
    {globe, gz} = if r2 < @rp * @rp, do: globe(x, y, r2, space), else: {nil, nil}

    # The ring plane where this line of sight crosses it.
    z = -y * a1 / a2
    {op, albedo} = ring(:math.sqrt(r2 + z * z) / @rp)

    front =
      if op > 0 and (gz == nil or z > gz) do
        # The globe's shadow on the rings, on the side away from the sun.
        b = dot({x, y, z}, sun)
        c = r2 + z * z - @rp * @rp
        {1 - op, op * albedo * if(b < 0 and b * b > c, do: 0.04, else: 1)}
      end

    mix(globe, front)
  end

  defp mix(nil, nil), do: nil
  defp mix(nil, {_, v}), do: {:value, v}
  defp mix({:value, g}, nil), do: {:value, g}
  defp mix({:value, g}, {keep, v}), do: {:value, g * keep + v}
  defp mix(globe, front), do: {globe, front}

  defp globe(x, y, r2, %{sun: {s0, s1, s2} = sun, axis: {_, a1, a2} = axis, e2: e2}) do
    z = :math.sqrt(@rp * @rp - r2)
    n = {x / @rp, y / @rp, z / @rp}
    lat = :math.asin(dot(n, axis))
    lon = :math.atan2(elem(n, 0), dot(n, e2))
    lit = smooth(-0.08, 0.4, dot(n, sun))
    # The rings' shadow: follow the light from here to the ring plane.
    s = -(y * a1 + z * a2) / dot(sun, axis)

    shade =
      if s > 0,
        do: 1 - 0.75 * elem(ring(JSMath.hypot(x + s * s0, y + s * s1, z + s * s2) / @rp), 0),
        else: 1

    light = {lit, shade, 0.7 + 0.3 * elem(n, 2)}

    # Unlit, the clouds (always above 0) are multiplied by 0.
    globe =
      if lit == 0,
        do: {:value, brightness(1, light)},
        else: {latitude(lat), lon, light}

    {globe, z}
  end

  defp brightness(cloud, {lit, shade, f}), do: 0.86 * cloud * lit * shade * f

  # What cloud/2 takes from the latitude alone.
  defp latitude(lat) do
    b = (lat - 0.42) / 0.12
    sl = abs(:math.sin(lat))
    {lat, 6 * lat, 4 * lat, lat * 21, :math.cos(lat), b * b, 1 - 0.35 * :math.pow(sl, 4)}
  end

  # Cloud brightness at a latitude and longitude: pale zones and dark belts
  # whose edges ripple with longitude, a dark line along each edge, an oval
  # storm, and darker poles.
  defp cloud({lat, lat6, lat4, lat21, clat, bb, polar}, lon) do
    w = lat + 0.05 * :math.sin(4 * lon + lat6) + 0.03 * :math.sin(9 * lon - lat4 + 1)
    # A pale zone on the equator, belts either side.
    s = :math.cos(w * 7.2)
    q = s / 0.16
    v = 0.5 + 0.42 * smooth(-0.35, 0.35, s) - 0.28 * :math.exp(-(q * q))
    v = v + 0.06 * :math.sin(lon * 7 + lat21)
    pi = :math.pi()
    dl = JSMath.mod(JSMath.mod(lon + 0.6, 2 * pi) + 3 * pi, 2 * pi) - pi
    a = dl * clat / 0.42
    d = a * a + bb
    v = if d < 1, do: if(d > 0.45, do: 0.3, else: 1), else: v
    v * polar
  end

  defp value({:value, v}, _spin), do: v

  defp value({{latitude, lon, light}, front}, spin) do
    g = brightness(cloud(latitude, lon - spin), light)

    case front do
      nil -> g
      {keep, v} -> g * keep + v
    end
  end

  @impl true
  def frame(%{cells: cells, stars: stars} = state, t, env) do
    spin = 2 * :math.pi() * t / @day
    last = tuple_size(@ramp) - 1

    grid =
      for row <- cells do
        row
        |> Enum.map(fn
          " " ->
            " "

          {samples, hits} ->
            sum = Enum.reduce(samples, 0, &(&2 + value(&1, spin)))
            i = min(last, max(1, JSMath.round(sum / hits * last)))
            elem(@ramp, if(env.paper, do: tuple_size(@ramp) - i, else: i))
        end)
        |> List.to_tuple()
      end
      |> List.to_tuple()

    # Stars go only where nothing else is, and one in three slowly dims.
    grid =
      Enum.reduce(stars, grid, fn {c, r, p}, grid ->
        line = elem(grid, r)

        if elem(line, c) == " " do
          ch =
            cond do
              p < 2 and :math.sin(t * 0.9 + p * 3) < -0.3 -> " "
              p < 4 -> "·"
              true -> "."
            end

          put_elem(grid, r, put_elem(line, c, ch))
        else
          grid
        end
      end)

    lines = for line <- Tuple.to_list(grid), do: Tuple.to_list(line)
    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
