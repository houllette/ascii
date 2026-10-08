defmodule AsciiArt.Pieces.JuliaSet do
  @moduledoc """
  A julia set changing shape as its constant c goes round.

  The Julia set of z*z + c, drawn as a glow on its edge, with c going round a
  circle so the set melts from one shape into the next.

  Ported from `src/pieces/julia-set.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "julia set",
    category: :generative,
    note: "a julia set changing shape as its constant c goes round",
    cols: 66,
    rows: 24,
    fps: 20,
    loop: 40
  }

  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # Seconds for c to go once round.
  @p 40
  # c's circle: it stays close to the Mandelbrot set's edge.
  @cx -0.4
  @r 0.68
  @max 120
  # The width of the view.
  @span 3.7
  # How far the glow reaches from the edge, in cells.
  @reach 4

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    dx = @span / cols
    # A cell is twice as tall as it is wide.
    dy = dx * 2
    half = div(rows, 2)

    %{
      dx: dx,
      ys: for(r <- 0..(half - 1), do: (r + 0.5 - half) * dy),
      xs: for(c <- 0..(cols - 1), do: (c + 0.5 - cols / 2) * dx)
    }
  end

  @impl true
  def frame(%{dx: dx, ys: ys, xs: xs} = state, t, _env) do
    # c starts at -0.4 + 0.68i.
    a = :math.pi() / 2 + 2 * :math.pi() * t / @p
    cr = @cx + @r * :math.cos(a)
    ci = @r * :math.sin(a)

    # The set is symmetric through the origin, so the bottom half is the top
    # turned round.
    top =
      for y0 <- ys do
        for x <- xs, do: cell(x, y0, cr, ci, dx)
      end

    lines = top ++ (top |> Enum.reverse() |> Enum.map(&Enum.reverse/1))
    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp cell(x, y, cr, ci, dx) do
    case orbit(x, y, 1, 0, 0, cr, ci) do
      # Inside: the glow is on the edge alone.
      :inside ->
        " "

      {m, ex, ey} ->
        z = :math.sqrt(m)
        h = JSMath.hypot(ex, ey)
        glow(0.5 * z * :math.log(z), h, dx)
    end
  end

  # A derivative of zero puts the edge infinitely far: k is 0.
  defp glow(_num, h, _dx) when h == 0, do: " "

  defp glow(num, h, dx) do
    # Cells to the edge.
    d = num / h / dx
    k = max(0, 1 - :math.pow(d / @reach, 0.6))
    n = tuple_size(@ramp)
    elem(@ramp, min(n - 1, floor(k * n)))
  end

  # The orbit of z, with its derivative, for the distance to the set.
  defp orbit(x, y, ex, ey, n, cr, ci) when n < @max do
    xx = x * x
    yy = y * y
    m = xx + yy

    if m > 1.0e4,
      do: {m, ex, ey},
      else:
        orbit(
          xx - yy + cr,
          2 * x * y + ci,
          2 * (x * ex - y * ey),
          2 * (x * ey + y * ex),
          n + 1,
          cr,
          ci
        )
  end

  defp orbit(_x, _y, _ex, _ey, _n, _cr, _ci), do: :inside
end
