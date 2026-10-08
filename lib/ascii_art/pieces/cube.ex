defmodule AsciiArt.Pieces.Cube do
  @moduledoc """
  A stippled hidden-line cube turning a quarter at a time.

  A cube drawn the way a drafting sheet draws it, in parallel projection with
  only the near edges and faces stippled by the light, turning by quarters.

  Ported from `src/pieces/cube.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Grid
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "cube",
    category: :shapes,
    note: "a stippled hidden-line cube turning a quarter at a time",
    cols: 32,
    rows: 18,
    fps: 24,
    loop: 24
  }

  # Cell width over cell height, rows per half-edge, the resting yaw (long
  # edges flat, receding edges one column a row), and looking down on the top.
  @cw 0.5
  @s 4.95
  @rest 0.21
  @pitch -0.43
  # Seconds to turn a quarter, and at rest after each turn.
  @turn 4
  @hold 2

  @corners for i <- 0..7,
               do:
                 {if(band(i, 1) > 0, do: 1, else: -1), if(band(i, 2) > 0, do: 1, else: -1),
                  if(band(i, 4) > 0, do: 1, else: -1)}
  @edges for i <- 0..7, b <- [1, 2, 4], band(i, b) == 0, do: {i, bor(i, b)}
  # Each face as its axis, its sign and its four corners in order around it.
  @faces (for k <- 0..2, s <- [0, 1] do
            [a, b] = for {v, j} <- Enum.with_index([1, 2, 4]), j != k, do: v
            base = bsl(s, k)

            {k, if(s == 1, do: 1, else: -1),
             [base, bor(base, a), bor(bor(base, a), b), bor(base, b)]}
          end)

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    # From the upper left, toward the eye at -z.
    light = [-0.35, 0.6, -0.72]

    {light_x, light_y, light_z} =
      light |> Enum.map(&(&1 / JSMath.hypot_list(light))) |> List.to_tuple()

    %{light: {light_x, light_y, light_z}}
  end

  defp ease(u) when u <= 0, do: 0
  defp ease(u) when u >= 1, do: 1
  defp ease(u), do: u * u * u * (u * (6 * u - 15) + 10)

  # A face's stipple by the light it catches, least ink to most: a sparse
  # lattice of dots, a checker of dots, a checker of colons.
  defp tone(0, c, r), do: if(rem(c + 2 * r, 4) == 0, do: ".", else: " ")
  defp tone(1, c, r), do: if(band(c + r, 1) == 1, do: ".", else: " ")
  defp tone(2, c, r), do: if(band(c + r, 1) == 1, do: ":", else: " ")

  @impl true
  def frame(state, t, env) do
    %{cols: cols, rows: rows} = @meta
    n = JSMath.floor(t / (@turn + @hold))
    yaw = @rest + :math.pi() / 2 * (n + ease((t - n * (@turn + @hold)) / @turn))
    cy = :math.cos(yaw)
    sy = :math.sin(yaw)
    cp = :math.cos(@pitch)
    sp = :math.sin(@pitch)

    turn = fn {x, y, z} ->
      z1 = z * cy - x * sy
      {x * cy + z * sy, y * cp - z1 * sp, y * sp + z1 * cp}
    end

    points =
      @corners
      |> Enum.map(fn v ->
        {x, y, _} = turn.(v)
        {JSMath.round(cols / 2 - 0.5 + x * @s / @cw), JSMath.round(rows / 2 - 0.5 - y * @s)}
      end)
      |> List.to_tuple()

    # A face shows when it turns toward the eye by more than a sliver; an edge
    # shows when either of its faces does.
    shown = for {k, s, _} <- @faces, do: turn.(axis(k, s))

    visible =
      for {{_, _, q}, {_, _, z}} <- Enum.zip(@faces, shown), z < -0.12, do: q

    seen = for {a, b} = e <- @edges, Enum.any?(visible, &(a in &1 and b in &1)), do: e

    grid =
      Enum.reduce(seen, Grid.new(cols, rows), fn {a, b}, g ->
        line(elem(points, a), elem(points, b), g)
      end)

    grid =
      Enum.reduce(seen, grid, fn {a, b}, g ->
        {ca, ra} = elem(points, a)
        {cb, rb} = elem(points, b)
        g |> Grid.put(ca, ra, "+") |> Grid.put(cb, rb, "+")
      end)

    # Every face in view takes a tone by the light it catches, ink meaning
    # light on a screen and shadow on paper.
    {lx, ly, lz} = state.light

    grid =
      @faces
      |> Enum.zip(shown)
      |> Enum.reduce(grid, fn
        {_, {_, _, z}}, g when z >= -0.12 ->
          g

        {{_, _, q}, {x, y, z}}, g ->
          lit = max(0, x * lx + y * ly + z * lz)
          k = min(2, JSMath.floor(lit * 3))
          k = if env.paper, do: 2 - k, else: k
          quad = Enum.map(q, &elem(points, &1))
          {xs, ys} = Enum.unzip(quad)

          for r <- Enum.min(ys)..Enum.max(ys), c <- Enum.min(xs)..Enum.max(xs), reduce: g do
            g ->
              if c >= 0 and c < cols and r >= 0 and r < rows and Grid.get(g, c, r) == " " and
                   inside?(quad, c, r, 0.45),
                 do: Grid.put(g, c, r, tone(k, c, r)),
                 else: g
          end
      end)

    {Grid.to_iodata(grid), nil, state}
  end

  defp axis(k, s), do: List.to_tuple(for j <- 0..2, do: if(j == k, do: s, else: 0))

  # One edge, between its corner cells but not on them. A shallow edge is runs
  # of - only, a row apart; a steeper one takes one / or \ a row, with _
  # carrying the edge along the foot of the row to where the next row picks up,
  # and one within a few degrees of upright is |.
  defp line({c0, r0}, {c1, r1}, grid) when r1 < r0, do: line({c1, r1}, {c0, r0}, grid)

  defp line({c0, r0}, {c1, r1}, grid) do
    dc = c1 - c0
    dr = r1 - r0
    s = JSMath.sign(dc)

    if 5 * dr < abs(dc) * @cw * 2 do
      Enum.reduce(Stream.iterate(c0 + s, &(&1 + s)) |> Enum.take_while(&(&1 != c1)), grid, fn c,
                                                                                              g ->
        Grid.put(g, c, JSMath.round(r0 + dr * (c - c0) / dc), "-")
      end)
    else
      ch =
        cond do
          3 * abs(dc) <= dr -> "|"
          s > 0 -> "\\"
          true -> "/"
        end

      at = fn r -> JSMath.round(c0 + dc * (r - r0) / dr) end

      Enum.reduce(r0..(r1 - 1)//1, grid, fn r, g ->
        g = if r > r0, do: Grid.put(g, at.(r), r, ch), else: g
        next = at.(r + 1)

        Stream.iterate(at.(r) + s, &(&1 + s))
        |> Enum.take_while(&((next - &1) * s > 0))
        |> Enum.reduce(g, &Grid.put(&2, &1, r, "_"))
      end)
    end
  end

  # Is (c, r) inside the convex quad, by more than m cells?
  defp inside?(quad, c, r, m) do
    pairs = Enum.zip(quad, tl(quad) ++ [hd(quad)])

    result =
      Enum.reduce_while(pairs, 0, fn {{x0, y0}, {x1, y1}}, sign ->
        ex = (x1 - x0) * @cw
        ey = y1 - y0
        d = ((c - x0) * @cw * ey - (r - y0) * ex) / JSMath.hypot(ex, ey)

        cond do
          abs(d) < m -> {:halt, false}
          sign != 0 and JSMath.sign(d) != sign -> {:halt, false}
          true -> {:cont, JSMath.sign(d)}
        end
      end)

    result != false
  end
end
