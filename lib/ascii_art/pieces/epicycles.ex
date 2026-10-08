defmodule AsciiArt.Pieces.Epicycles do
  @moduledoc """
  A chain of turning circles whose tip traces a star.

  A five-pointed star as a Fourier series. Each circle turns at a whole
  multiple of the first while riding the rim of the one before, and the tip
  of the chain traces the star.

  Ported from `src/pieces/epicycles.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "epicycles",
    category: :generative,
    note: "a chain of turning circles whose tip traces a star",
    cols: 60,
    rows: 24,
    fps: 30
  }

  # Circles in the chain: every term a five-fold star has up to k = 39.
  @terms 16
  # Seconds to trace the figure once.
  @period 10
  # Share of the figure kept behind the tip; past @fade of the trail it fades.
  @trail 0.9
  @fade 0.8
  # Points along one trace when it is laid into cells.
  @samples 2400
  # A cell is about twice as tall as it is wide.
  @aspect 0.5
  # Only these circles, counted from the largest, show their rims.
  @rims [1]
  # Arms shorter than this, in columns, are not drawn apart.
  @joint 1.5
  # Where on the figure the tip is at t = 0: along the left arm.
  @phase 0.12

  @impl true
  def meta, do: @meta

  # The star's outline, sampled evenly by length, as {x, y} with y up.
  defp star(n) do
    v =
      for j <- 0..9 do
        a = :math.pi() / 2 + j * :math.pi() / 5
        r = if rem(j, 2) == 1, do: 0.4, else: 1
        {r * :math.cos(a), r * :math.sin(a)}
      end
      |> List.to_tuple()

    for i <- 0..(n - 1) do
      d = i / n * 10
      j = floor(d)
      f = d - j
      {ax, ay} = elem(v, j)
      {bx, by} = elem(v, rem(j + 1, 10))
      {ax + (bx - ax) * f, ay + (by - ay) * f}
    end
  end

  # The heading of a stroke picks its glyph, with rows counted double. Shallow
  # strokes sit high, middle or low in the cell, wherever the line crosses it.
  defp pen(dx, dy, f) do
    a = :math.atan2(dy, dx) * 180 / :math.pi()
    a = if a < 0, do: a + 180, else: a
    flat = min(a, 180 - a)

    cond do
      flat < 8 -> if f < 0.62, do: "-", else: "_"
      flat < 42 -> pen_shallow(f)
      a < 80 -> "/"
      a < 100 -> "|"
      true -> "\\"
    end
  end

  defp pen_shallow(f) when f < 0.3, do: "'"
  defp pen_shallow(f) when f < 0.68, do: "-"
  defp pen_shallow(_f), do: "_"

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    pts = star(500)
    n = length(pts)

    # Discrete Fourier transform: every term is a circle of radius |c|
    # turning k times per trace. Keep the biggest, largest first.
    chain =
      for k <- -40..40 do
        {re, im, _} =
          Enum.reduce(pts, {0, 0, 0}, fn {x, y}, {re, im, i} ->
            a = -2 * :math.pi() * k * i / n
            c = :math.cos(a)
            s = :math.sin(a)
            {re + (x * c - y * s), im + (x * s + y * c), i + 1}
          end)

        %{k: k, re: re / n, im: im / n, r: JSMath.hypot(re, im) / n}
      end
      |> Enum.sort_by(& &1.r, :desc)
      |> Enum.take(@terms)

    # Fit the traced figure to the frame.
    path = for i <- 0..(@samples - 1), do: tip(chain, i / @samples * 2 * :math.pi())

    {x0, x1, y0, y1} =
      Enum.reduce(path, {1, -1, 1, -1}, fn {x, y}, {x0, x1, y0, y1} ->
        {min(x0, x), max(x1, x), min(y0, y), max(y1, y)}
      end)

    # The points reach just past a cell's centre line, so each ends in one cell.
    s = min((cols - 8) / (x1 - x0), (rows - 2.3) / @aspect / (y1 - y0))
    fit = {s, (x0 + x1) / 2, (y0 + y1) / 2}
    p = path |> Enum.map(fn {x, y} -> {to_col(fit, x), to_row(fit, y)} end) |> List.to_tuple()
    cells = lay(p)

    %{
      chain: Enum.map(chain, &{&1.k, &1.re, &1.im}),
      radii: chain |> Enum.map(& &1.r) |> List.to_tuple(),
      fit: fit,
      cells: cells,
      figure: MapSet.new(cells, &elem(&1, 0))
    }
  end

  # The chain's tip: the sum of every term at theta.
  defp tip(chain, theta) do
    Enum.reduce(chain, {0, 0}, fn %{k: k, re: re, im: im}, {x, y} ->
      c = :math.cos(k * theta)
      s = :math.sin(k * theta)
      {x + (re * c - im * s), y + (re * s + im * c)}
    end)
  end

  defp to_col({s, mx, _my}, x), do: @meta.cols / 2 + (x - mx) * s
  defp to_row({s, _mx, my}, y), do: @meta.rows / 2 - (y - my) * s * @aspect

  # Lay the trace into cells once. Where it runs shallow it takes the cell it
  # crosses each column's centre in, where steep the cell for each row's
  # centre, so every edge is one cell wide; any gap left is bridged.
  defp lay(p) do
    cols = @meta.cols

    rev =
      Enum.reduce(0..(@samples - 1), [], fn i, cells ->
        {ax, ay} = elem(p, i)
        {bx, by} = elem(p, rem(i + 1, @samples))
        {px, py} = elem(p, rem(i - 2 + @samples, @samples))
        {nx, ny} = elem(p, rem(i + 3, @samples))
        steep = abs(by - ay) > abs(bx - ax)
        {a, b} = if steep, do: {ay, by}, else: {ax, bx}
        hi = max(a, b)

        ceil(min(a, b) - 0.5)
        |> Stream.iterate(&(&1 + 1))
        |> Enum.take_while(&(&1 + 0.5 < hi))
        |> Enum.reduce(cells, fn k, cells ->
          s = (k + 0.5 - a) / (b - a)
          x = ax + (bx - ax) * s
          y = ay + (by - ay) * s
          g = pen(nx - px, (py - ny) / @aspect, y - floor(y))

          if steep,
            do: add(cells, floor(x), k, i, g),
            else: add(cells, k, floor(y), i, g)
        end)
      end)

    cells = Enum.reverse(rev)
    {first_c, first_r, _, _} = hd(cells)

    rev
    |> drop_closing(first_c, first_r)
    |> Enum.reverse()
    |> Enum.map(fn {c, r, i, g} -> {c + r * cols, i, g} end)
  end

  # The newest cell is at the head of the list.
  defp add([{c, r, _, _} | _] = cells, c, r, _i, _g), do: cells
  defp add(cells, c, r, i, g), do: [{c, r, i, g} | bridge(cells, c, r, i, g)]

  defp bridge([{pc, pr, _, _} | _] = cells, c, r, i, g)
       when max(abs(c - pc), abs(r - pr)) > 1,
       do:
         bridge([{pc + JSMath.sign(c - pc), pr + JSMath.sign(r - pr), i, g} | cells], c, r, i, g)

  defp bridge(cells, _c, _r, _i, _g), do: cells

  # Cells at the end of the trace that land back on its first cell go.
  defp drop_closing([{c, r, _, _} | [_ | _] = rest], c, r), do: drop_closing(rest, c, r)
  defp drop_closing(cells, _c, _r), do: cells

  @impl true
  def frame(state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    %{chain: chain, radii: radii, fit: {s, _, _} = fit, cells: cells, figure: figure} = state
    u = JSMath.mod(t / @period + @phase, 1)
    head = u * @samples
    theta = u * 2 * :math.pi()

    joints = joints(chain, radii, fit, theta, s)
    jt = List.to_tuple(joints)

    grid =
      Enum.reduce(@rims, %{}, fn j, grid ->
        a = elem(radii, j) * s
        rim(grid, figure, a, a * @aspect, elem(jt, j))
      end)

    grid =
      joints
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(grid, fn [{ax, ay}, {bx, by}], grid ->
        n = JSMath.round(max(abs(bx - ax), abs(by - ay)))

        Enum.reduce(1..(n - 1)//1, grid, fn k, grid ->
          dot(grid, figure, ax + (bx - ax) * k / n, ay + (by - ay) * k / n)
        end)
      end)

    # The trace behind the tip, its far end fading through ':' to '.'.
    grid =
      Enum.reduce(cells, grid, fn {at, i, g}, grid ->
        age = JSMath.mod(head - i + @samples, @samples) / @samples / @trail

        cond do
          age > 1 -> grid
          age < @fade -> Map.put(grid, at, g)
          age < 0.95 -> Map.put(grid, at, ":")
          true -> Map.put(grid, at, ".")
        end
      end)

    # The centre, and a pivot at the middle of each circle that shows its rim.
    grid = put(grid, elem(jt, 0), "+")
    grid = Enum.reduce(@rims, grid, fn j, grid -> put(grid, elem(jt, j), "o") end)
    grid = put(grid, List.last(joints), "@")

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(grid, c + r * cols, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # Each partial sum of the chain is a joint; short arms are skipped, the tip never.
  defp joints(chain, radii, fit, theta, s) do
    {rev, _, _} =
      chain
      |> Enum.with_index(1)
      |> Enum.reduce({[{to_col(fit, 0), to_row(fit, 0)}], 0, 0}, fn {{k, re, im}, j},
                                                                    {joints, x, y} ->
        c = :math.cos(k * theta)
        sn = :math.sin(k * theta)
        x = x + (re * c - im * sn)
        y = y + (re * sn + im * c)

        if j == @terms or elem(radii, j - 1) * s > @joint,
          do: {[{to_col(fit, x), to_row(fit, y)} | joints], x, y},
          else: {joints, x, y}
      end)

    Enum.reverse(rev)
  end

  # A rim takes one cell a column where it runs flat and one a row where it
  # runs steep, so it stays a single dotted line all the way round.
  defp rim(grid, figure, a, b, {pc, pr}) do
    grid =
      ceil(pc - a - 0.5)
      |> Stream.iterate(&(&1 + 1))
      |> Enum.take_while(&(&1 + 0.5 < pc + a))
      |> Enum.reduce(grid, fn c, grid ->
        u = (c + 0.5 - pc) / a

        case root(u) do
          s when s != nil and b / a * abs(u) <= s ->
            grid |> dot(figure, c + 0.5, pr - b * s) |> dot(figure, c + 0.5, pr + b * s)

          _ ->
            grid
        end
      end)

    ceil(pr - b - 0.5)
    |> Stream.iterate(&(&1 + 1))
    |> Enum.take_while(&(&1 + 0.5 < pr + b))
    |> Enum.reduce(grid, fn r, grid ->
      v = (r + 0.5 - pr) / b

      case root(v) do
        s when s != nil and a / b * abs(v) <= s ->
          grid |> dot(figure, pc - a * s, r + 0.5) |> dot(figure, pc + a * s, r + 0.5)

        _ ->
          grid
      end
    end)
  end

  # sqrt(1 - u * u), or nil where JS takes the root of a negative (NaN, which
  # fails every comparison).
  defp root(u) do
    w = 1 - u * u
    if w < 0, do: nil, else: :math.sqrt(w)
  end

  # The mechanism is dotted, rims and arms alike, and never covers the figure.
  defp dot(grid, figure, x, y) do
    %{cols: cols, rows: rows} = @meta
    c = floor(x)
    r = floor(y)
    at = c + r * cols

    if c >= 0 and c < cols and r >= 0 and r < rows and not MapSet.member?(figure, at),
      do: Map.put(grid, at, "·"),
      else: grid
  end

  defp put(grid, {x, y}, ch) do
    %{cols: cols, rows: rows} = @meta
    c = floor(x)
    r = floor(y)

    if c >= 0 and c < cols and r >= 0 and r < rows,
      do: Map.put(grid, c + r * cols, ch),
      else: grid
  end
end
