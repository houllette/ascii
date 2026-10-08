defmodule AsciiArt.Pieces.BlackHole do
  @moduledoc """
  A black hole, its lensed disk turning, one side brighter.

  A Schwarzschild black hole and its disk, seen almost edge on. Rays are
  traced once through the bent space; then only the gas turns, faster near
  the hole, the side coming toward us brighter.

  Ported from `src/pieces/black-hole.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Rand

  @meta %AsciiArt.Meta{
    name: "black hole",
    category: :space,
    note: "a black hole, its lensed disk turning, one side brighter",
    cols: 64,
    rows: 20,
    fps: 15,
    loop: 60
  }

  # The disk is light, not shade, so the ramp keeps its sense on paper too.
  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # Rays per cell across and down.
  @sx 3
  @sy 4
  # Camera distance, the disk's inner and outer edge, in Schwarzschild radii.
  @d 30
  @inner 3
  @outer 9
  # The camera's height above the disk plane, in radians.
  @tilt 0.15
  # Half the view's width, as a tangent.
  @span 0.34
  # Exposure, and the faintest light that shows.
  @gain 1.6
  @floor 0.03
  # Seconds until the gas comes round to where it started.
  @loop 60
  # Rings of gas, each turning a whole number of times a loop.
  @bands 12
  # Turns a loop at the inner edge; Kepler sets the rest.
  @spin 7
  # The table of paths: impact parameters and step.
  @bmax 12
  @nb 1500
  @h 0.02
  @tab 256

  @compile {:inline, at: 2}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    # One cell's width as a tangent; it stands twice as tall.
    cw = 2 * @span / cols
    s = :math.sin(@tilt)
    c = :math.cos(@tilt)

    {bands, rand} = bands(Rand.seed(17))

    # Upstream traces the rays row by row, pushing each crossing into its
    # cell; taking each cell's rays in that same order keeps its crossings,
    # and so its sums, in upstream's order. Only the paths some ray uses are
    # stepped, each once.
    {cells, _paths} =
      Enum.map_reduce(0..(rows * cols - 1), %{}, fn k, paths ->
        cell(div(k, cols), rem(k, cols), cw, s, c, paths)
      end)

    # A few faint stars where the sky is clear.
    {cells, _} =
      Enum.map_reduce(cells, rand, fn
        {h, true}, rand ->
          {x, rand} = Rand.next(rand)
          {{h, x < 0.03}, rand}

        {h, false}, rand ->
          {{h, false}, rand}
      end)

    %{
      tabs: bands |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
      turns: Enum.map(bands, &elem(&1, 1)),
      rows: Enum.chunk_every(cells, cols)
    }
  end

  # Each band's gas is a ring of noise: a few whole harmonics, so it closes.
  defp bands(rand) do
    Enum.map_reduce(0..(@bands - 1), rand, fn b, rand ->
      r = @inner + (@outer - @inner) * b / (@bands - 1)
      turns = max(1, JSMath.round(@spin * :math.pow(@inner / r, 1.5)))

      {waves, rand} =
        Enum.map_reduce([2, 3, 5, 8, 13], rand, fn k, rand ->
          {p, rand} = Rand.next(rand)
          {a, rand} = Rand.next(rand)
          {{k, p * 6.283, (0.5 + a) / :math.sqrt(k)}, rand}
        end)

      tab =
        for i <- 0..(@tab - 1) do
          Enum.reduce(waves, 0, fn {k, p, a}, v ->
            JSMath.fround(v + a * :math.sin(k * 2 * :math.pi() * i / @tab + p))
          end)
        end

      {lo, hi} = Enum.min_max(tab)
      tab = for v <- tab, do: JSMath.fround(0.45 + 0.55 * (v - lo) / (hi - lo))
      {{List.to_tuple(tab), turns}, rand}
    end)
  end

  # A cell's crossings, in the order upstream pushes them, and whether no ray
  # through it met the hole or the disk.
  defp cell(row, col, cw, s, c, paths) do
    rays =
      for j <- (row * @sy)..(row * @sy + @sy - 1),
          i <- (col * @sx)..(col * @sx + @sx - 1),
          do: {j, i}

    {hits, {empty, paths}} =
      Enum.flat_map_reduce(rays, {true, paths}, fn {j, i}, {empty, paths} ->
        {hits, hole, paths} = ray(j, i, cw, s, c, paths)
        {hits, {empty and not hole and hits == [], paths}}
      end)

    {{hits, empty}, paths}
  end

  # Each ray: its plane (e1 toward the camera, e2 along the ray), then the
  # angles where its height s cos a + e2y sin a is zero, a half turn apart.
  # A crossing inside the disk keeps what never changes: bands, angle, weight.
  defp ray(j, i, cw, s, c, paths) do
    %{cols: cols, rows: rows} = @meta
    # Half a row high: the arc over the hole is the taller one.
    y = (rows / 2 + 0.5 - (j + 0.5) / @sy) * 2 * cw
    x = ((i + 0.5) / @sx - cols / 2) * cw
    n = JSMath.hypot(x, y, 1)
    d0 = x / n
    d1 = (y * c - s) / n
    d2 = (y * s + c) / n
    out = d1 * s - d2 * c
    side = :math.sqrt(1 - out * out)
    e2 = {d0 / side, (d1 - out * s) / side, (d2 + out * c) / side}
    index = min(@nb - 1, JSMath.floor(@d * side * @nb / @bmax))

    {us, paths} =
      case paths do
        %{^index => us} ->
          {us, paths}

        _ ->
          us = path(index)
          {us, Map.put(paths, index, us)}
      end

    len = tuple_size(us)
    hole = elem(us, len - 1) >= 1
    # Images that wind more than once round the hole are thinner than a cell
    # and only speckle the shadow, so they are left out.
    stop = min((len - 1) * @h, 5.6)
    start = JSMath.mod(:math.atan2(-s, elem(e2, 1)) + 2 * :math.pi(), :math.pi())
    {crossings(start, stop, 1, us, e2, c, []), hole, paths}
  end

  defp crossings(a, stop, light, us, {e0, _, e2} = e, c, acc) when a < stop do
    p = a / @h
    q = JSMath.floor(p)
    uq = elem(us, q)
    r = 1 / (uq + (elem(us, q + 1) - uq) * (p - q))

    if r <= @inner or r >= @outer do
      crossings(a + :math.pi(), stop, light, us, e, c, acc)
    else
      sa = :math.sin(a)
      phi = :math.atan2(sa * e2 - :math.cos(a) * c, sa * e0)
      rel = (r - @inner) / (@outer - @inner)
      edge = min(1, (r - @inner) / 0.7) * (1 - rel * rel)
      doppler = 1 - 0.5 * :math.cos(phi)
      pos = (r - @inner) / (@outer - @inner) * (@bands - 1)
      b0 = min(@bands - 2, JSMath.floor(pos))
      w = light * edge * doppler * :math.pow(@inner / r, 1.5) / (@sx * @sy)
      # A crossing seen through the disk is dimmer.
      crossings(a + :math.pi(), stop, light * 0.45, us, e, c, [{b0, pos - b0, phi, w} | acc])
    end
  end

  defp crossings(_a, _stop, _light, _us, _e, _c, acc), do: Enum.reverse(acc)

  # A ray stays in a plane through the hole, and its path there depends only
  # on its impact parameter b. In that plane u = 1/r obeys u'' = 1.5u^2 - u in
  # the angle a swept from the camera; each path is stepped with RK4 until it
  # falls in or leaves, and kept as u at every step (a Float32Array).
  defp path(n) do
    b = (n + 0.5) / @nb * @bmax
    u = 1 / @d
    q = b / @d
    w = :math.sqrt(1 - q * q) / b
    [u | step(u, w, [])] |> List.to_tuple()
  end

  defp step(u, w, acc) do
    if u < 1 and (u > 1 / (@outer + 1) or w > 0) do
      k1 = w
      l1 = f(u)
      k2 = w + @h / 2 * l1
      l2 = f(u + @h / 2 * k1)
      k3 = w + @h / 2 * l2
      l3 = f(u + @h / 2 * k2)
      k4 = w + @h * l3
      l4 = f(u + @h * k3)
      u = u + @h / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
      w = w + @h / 6 * (l1 + 2 * l2 + 2 * l3 + l4)
      step(u, w, [JSMath.fround(u) | acc])
    else
      Enum.reverse(acc)
    end
  end

  defp f(u), do: 1.5 * u * u - u

  defp at(tab, a) do
    i = rem(JSMath.floor(a / (2 * :math.pi()) * @tab), @tab)
    elem(tab, if(i < 0, do: i + @tab, else: i))
  end

  @impl true
  def frame(%{tabs: tabs, turns: turns, rows: rows} = state, t, _env) do
    turn = 2 * :math.pi() * JSMath.mod(t, @loop) / @loop
    shifts = turns |> Enum.map(&(&1 * turn)) |> List.to_tuple()
    last = tuple_size(@ramp) - 1

    lines =
      for row <- rows do
        for {h, star} <- row do
          sum =
            Enum.reduce(h, 0, fn {b, fr, phi, w}, sum ->
              g0 = at(elem(tabs, b), phi - elem(shifts, b))
              g1 = at(elem(tabs, b + 1), phi - elem(shifts, b + 1))
              sum + w * (g0 + (g1 - g0) * fr)
            end)

          ch = elem(@ramp, JSMath.round(level(sum) * last))
          if ch == " " and star, do: ".", else: ch
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp level(sum) do
    v = min(1, max(0, sum * @gain - @floor) / (1 - @floor))

    cond do
      v == 0 -> 0
      v == 1 -> 1
      true -> :math.pow(v, 0.75)
    end
  end
end
