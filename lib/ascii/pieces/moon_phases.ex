defmodule Ascii.Pieces.MoonPhases do
  @moduledoc """
  The moon waxing and waning, its maria darker in the light.

  The moon through one lunar month. The sun swings round behind it, so the
  terminator sweeps across the sphere and back again.

  Ported from `src/pieces/moon-phases.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  alias Ascii.Kit.Rand

  @meta %Ascii.Meta{
    name: "moon phases",
    category: :space,
    note: "the moon waxing and waning, its maria darker in the light",
    cols: 46,
    rows: 23,
    fps: 15,
    loop: 24
  }

  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @n 9
  # Seconds for new moon to new moon.
  @month 24
  # Phase at t = 0, in radians past new moon: a young crescent.
  @start 0.95
  # Samples per cell each way.
  @ss 3

  # The near side's seas as ellipses on the disk, x east and y north, radius
  # 1: centre, radii, how much darker, and a tilt in radians.
  @maria [
    # Oceanus Procellarum
    {-0.62, 0.08, 0.28, 0.5, 0.62, 0},
    # Imbrium
    {-0.3, 0.45, 0.27, 0.21, 0.7, 0},
    # Frigoris, west
    {-0.3, 0.71, 0.25, 0.1, 0.55, 0.25},
    # Frigoris, east
    {0.14, 0.79, 0.22, 0.085, 0.5, -0.2},
    # Serenitatis
    {0.19, 0.42, 0.15, 0.14, 0.7, 0},
    # Tranquillitatis
    {0.38, 0.12, 0.21, 0.16, 0.7, 0},
    # Vaporum
    {0.05, 0.25, 0.09, 0.06, 0.5, 0},
    # Insularum
    {-0.28, 0.08, 0.12, 0.09, 0.4, 0},
    # Crisium
    {0.75, 0.3, 0.1, 0.14, 0.72, 0},
    # Fecunditatis
    {0.62, -0.12, 0.12, 0.2, 0.62, 0},
    # Nectaris
    {0.42, -0.28, 0.09, 0.09, 0.62, 0},
    # Nubium
    {-0.2, -0.34, 0.19, 0.14, 0.6, 0},
    # Humorum
    {-0.52, -0.43, 0.09, 0.1, 0.65, 0},
    # Grimaldi
    {-0.88, -0.06, 0.05, 0.08, 0.5, 0}
  ]
  # Young bright craters: Tycho, Copernicus, Kepler, Aristarchus.
  @craters [
    {-0.15, -0.72, 0.09, 0.4},
    {-0.33, 0.17, 0.05, 0.2},
    {-0.6, 0.14, 0.035, 0.15},
    {-0.75, 0.38, 0.03, 0.3}
  ]
  # Tycho's rays: direction and length.
  @rays [{1.75, 0.55}, {1.3, 0.4}, {2.3, 0.35}, {0.4, 0.3}, {3.1, 0.3}, {-0.6, 0.22}, {4.1, 0.2}]
  @tycho hd(@craters)

  @compile {:inline, smooth: 3}

  @impl true
  def meta, do: @meta

  defp smooth(a, b, x) do
    u = min(1, max(0, (x - a) / (b - a)))
    u * u * (3 - 2 * u)
  end

  # How bright the ground is at a point of the disk, before any light falls
  # on it.
  defp albedo(x, y, maria) do
    alb =
      Enum.reduce(maria, 1, fn {mx, my, rx, ry, k, c, s}, alb ->
        dx = x - mx
        dy = y - my

        alb -
          k * (1 - smooth(0.55, 1, JSMath.hypot((dx * c + dy * s) / rx, (dy * c - dx * s) / ry)))
      end)

    alb =
      Enum.reduce(@craters, max(0.3, alb), fn {mx, my, rr, k}, alb ->
        alb + k * (1 - smooth(0.3, 1, JSMath.hypot(x - mx, y - my) / rr))
      end)

    {tx, ty, tr, _} = @tycho
    dx = x - tx
    dy = y - ty
    d = JSMath.hypot(dx, dy)
    a = :math.atan2(dy, dx)

    alb =
      Enum.reduce(@rays, alb, fn {at, len}, alb ->
        off = abs(:math.atan2(:math.sin(a - at), :math.cos(a - at)))

        if d > tr and d < len and off < 1 do
          q = off * d / 0.03
          alb + 0.3 * (1 - d / len) * :math.exp(-(q * q))
        else
          alb
        end
      end)

    min(1.35, alb)
  end

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    cx = cols / 2
    cy = rows / 2
    # Radius in rows; it spans twice as many columns.
    rr = rows / 2 - 1

    maria =
      for {mx, my, rx, ry, k, rot} <- @maria,
          do: {mx, my, rx, ry, k, :math.cos(rot), :math.sin(rot)}

    # Every sample inside the disk keeps its normal and its albedo, and every
    # cell its mean albedo, which is all that shows in earthshine.
    samples =
      for r <- 0..(rows - 1), c <- 0..(cols - 1) do
        for j <- 0..(@ss - 1),
            i <- 0..(@ss - 1),
            x = (c + (i + 0.5) / @ss - cx) / (2 * rr),
            y = (cy - r - (j + 0.5) / @ss) / rr,
            d = x * x + y * y,
            d < 1,
            do: {x, y, :math.sqrt(1 - d), albedo(x, y, maria)}
      end
      |> List.to_tuple()

    inside = fn c, r ->
      c >= 0 and c < cols and r >= 0 and r < rows and
        length(elem(samples, r * cols + c)) * 4 * 2 >= 4 * @ss * @ss
    end

    # A cell on the rim, where the night side is drawn as a faint outline.
    {cells, _} =
      Enum.map_reduce(0..(rows * cols - 1), Rand.seed(7), fn k, rand ->
        r = div(k, cols)
        c = rem(k, cols)

        if inside.(c, r) do
          rim =
            not (inside.(c - 1, r) and inside.(c + 1, r) and inside.(c, r - 1) and
                   inside.(c, r + 1))

          {disk_cell(elem(samples, k), rim), rand}
        else
          star(JSMath.hypot((c + 0.5 - cx) / (2 * rr), (cy - r - 0.5) / rr), rand)
        end
      end)

    %{rows: Enum.chunk_every(cells, cols)}
  end

  defp disk_cell(s, rim) do
    count = length(s)
    ground = Enum.reduce(s, 0, fn {_, _, _, alb}, g -> JSMath.fround(g + alb / count) end)
    {s, count, rim, ground}
  end

  defp star(d, rand) when d > 1.12 do
    {a, rand} = Rand.next(rand)

    if a < 0.022 do
      {b, rand} = Rand.next(rand)
      {if(b < 0.25, do: "+", else: "."), rand}
    else
      {" ", rand}
    end
  end

  defp star(_d, rand), do: {" ", rand}

  @impl true
  def frame(%{rows: rows} = state, t, env) do
    ph = @start + 2 * :math.pi() * JSMath.mod(t, @month) / @month
    sin = :math.sin(ph)
    cos = :math.cos(ph)
    m = JSMath.hypot(sin, 0.12, cos)
    light = {sin / m, 0.12 / m, -cos / m}
    # Near new moon the earth is nearly full in the moon's sky, and its light
    # shows the night side's highlands faintly.
    earthshine = smooth(0, 0.5, cos)

    lines =
      for row <- rows do
        for cell <- row, do: cell(cell, light, earthshine, env.paper)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cell(ch, _light, _earthshine, _paper) when is_binary(ch), do: ch

  # Mostly Lommel-Seeliger, which keeps the full moon nearly flat, with a
  # little Lambert so the ball still reads as round.
  defp cell({s, count, rim, ground}, {lx, ly, lz}, earthshine, paper) do
    sum =
      Enum.reduce(s, 0, fn {x, y, z, alb}, sum ->
        mu0 = x * lx + y * ly + z * lz
        if mu0 <= 0, do: sum, else: sum + alb * (0.3 * mu0 + 0.7 * 2 * mu0 / (mu0 + z))
      end)

    v = min(1, sum / count)

    i =
      cond do
        v >= 0.015 -> 1 + JSMath.round(v * (@n - 1))
        rim or earthshine * ground > 0.72 -> 1
        true -> 0
      end

    elem(@ramp, if(paper, do: @n - i, else: i))
  end
end
