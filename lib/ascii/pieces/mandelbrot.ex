defmodule Ascii.Pieces.Mandelbrot do
  @moduledoc """
  A slow zoom into seahorse valley and back out again.

  The Mandelbrot set, zooming slowly into seahorse valley, the crack between
  the main cardioid and the disc to its left, then back out.

  Ported from `src/pieces/mandelbrot.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "mandelbrot",
    category: :generative,
    note: "a slow zoom into seahorse valley and back out again",
    cols: 64,
    rows: 26,
    fps: 15,
    loop: 48
  }

  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # Seconds to zoom in and back out.
  @p 48
  # Start just after the turn, so the zoom is already under way.
  @t0 1.5
  # Where the zoom heads: the centre of the deepest curl.
  @tx -0.74435
  @ty 0.12119
  # The centre and width of the whole set.
  @cx -0.75
  @span 3
  # Samples per cell each way, so fine filaments blur rather than flicker.
  @ss 2
  @s @ss * @ss
  # Octaves of cells out from the set over which the glow fades.
  @wide 3
  @narrow 1.2

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta

    # Each sample's offset from the frame's centre, in cells: across, and down.
    offsets =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          for j <- 0..(@s - 1) do
            {c + (rem(j, @ss) + 0.5) / @ss - cols / 2, r + (div(j, @ss) + 0.5) / @ss - rows / 2}
          end
        end
      end

    # The deepest zoom: one seahorse's curled tail.
    %{deep: :math.log(6000), offsets: offsets}
  end

  @impl true
  def frame(%{deep: deep, offsets: offsets} = state, t, env) do
    z = :math.exp(deep * (1 - :math.cos(2 * :math.pi() * (t + @t0) / @p)) / 2)
    # Moving the centre with the zoom keeps the target still on screen.
    cx = @tx + (@cx - @tx) / z
    cy = @ty - @ty / z
    dx = @span / z / @meta.cols
    # A cell is twice as tall as it is wide.
    dy = dx * 2
    max = JSMath.round(120 + 60 * :math.log2(z))
    edge = @wide + (@narrow - @wide) * :math.log(z) / deep
    view = {cx, cy, dx, dy, max, edge}
    set = if env.paper, do: "@", else: " "

    lines =
      for row <- offsets do
        for samples <- row, do: cell(samples, view, set)
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cell(samples, view, set) do
    {ink, inside} = Enum.reduce(samples, {0, 0}, &sample(&1, &2, view))

    # A cell the boundary runs through is at full glow. The set itself is
    # dark: left bare on a dark page, inked on paper.
    if inside == @s do
      set
    else
      n = tuple_size(@ramp)
      elem(@ramp, min(n - 1, floor((ink + inside) / @s * n)))
    end
  end

  defp sample({ox, oy}, {ink, inside}, {cx, cy, dx, dy, max, edge}) do
    x0 = cx + ox * dx
    y0 = cy - oy * dy
    # Inside the main cardioid or the disc beside it: no need to iterate.
    q = (x0 - 0.25) * (x0 - 0.25) + y0 * y0

    if q * (q + x0 - 0.25) < 0.25 * y0 * y0 or (x0 + 1) * (x0 + 1) + y0 * y0 < 0.0625 do
      {ink, inside + 1}
    else
      case orbit(0.0, 0.0, 0.0, 0.0, 0, max, x0, y0) do
        :inside -> {ink, inside + 1}
        {m, u, v} -> {ink + glow(m, JSMath.hypot(u, v), dx, edge), inside}
      end
    end
  end

  # A glow that hugs the boundary, measured in cells: wide on the whole set,
  # narrower deep down so the curls stay apart. A derivative of zero puts the
  # boundary infinitely far.
  defp glow(_m, h, _dx, _edge) when h == 0, do: 0

  defp glow(m, h, dx, edge) do
    d = 0.5 * :math.sqrt(m) * :math.log(m) / h / dx
    max(0, 1 - :math.log2(1 + d) / edge)
  end

  # Iterate z, and its derivative for the distance to the set.
  defp orbit(x, y, u, v, n, max, x0, y0)
       when n < max and is_float(x) and is_float(y) and is_float(u) and is_float(v) do
    nu = 2.0 * (x * u - y * v) + 1.0
    nv = 2.0 * (x * v + y * u)
    xx = x * x
    yy = y * y
    ny = 2.0 * x * y + y0
    nx = xx - yy + x0
    m = nx * nx + ny * ny

    if m > 1.0e6, do: {m, nu, nv}, else: orbit(nx, ny, nu, nv, n + 1, max, x0, y0)
  end

  defp orbit(_x, _y, _u, _v, _n, _max, _x0, _y0), do: :inside
end
