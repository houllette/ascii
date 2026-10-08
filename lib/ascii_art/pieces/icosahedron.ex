defmodule AsciiArt.Pieces.Icosahedron do
  @moduledoc """
  A wireframe icosahedron turning, its hidden edges dotted.

  A wireframe icosahedron turning on two axes. Edges on the near side are
  solid lines, the hidden ones behind are dotted.

  Ported from `src/pieces/icosahedron.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "icosahedron",
    category: :shapes,
    note: "a wireframe icosahedron turning, its hidden edges dotted",
    cols: 46,
    rows: 22,
    fps: 30
  }

  @cols 46
  @rows 22
  # Rows per column at which a line changes style: flat, shallow, diagonal,
  # steep, upright. A slope near a boundary keeps the style it had last frame.
  @limits {0.2, 0.38, 1, 2.1}
  # Eye to centre, in circumradii.
  @d 4
  @aspect 0.5

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    p = (1 + :math.sqrt(5)) / 2
    n = 1 / JSMath.hypot(1, p)

    verts =
      for a <- [-1, 1],
          b <- [-1, 1],
          v <- [{0.0, a * n, b * p * n}, {a * n, b * p * n, 0.0}, {b * p * n, 0.0, a * n}],
          do: v

    vt = List.to_tuple(verts)

    # Edges join vertices one edge length (2n) apart; faces are triangles of edges.
    near? = fn i, j ->
      {xi, yi, zi} = elem(vt, i)
      {xj, yj, zj} = elem(vt, j)
      abs(JSMath.hypot(xi - xj, yi - yj, zi - zj) - 2 * n) < 1.0e-6
    end

    pairs = for i <- 0..11, j <- (i + 1)..11//1, near?.(i, j), do: {i, j}
    faces = for {i, j} <- pairs, k <- (j + 1)..11//1, near?.(i, k) and near?.(j, k), do: [i, j, k]
    indexed = Enum.with_index(faces)

    edges =
      for {i, j} <- pairs do
        [m1, m2] = for {f, m} <- indexed, i in f and j in f, do: m
        {i, j, m1, m2}
      end

    %{
      verts: verts,
      faces: faces,
      edges: edges,
      vertex_faces: List.to_tuple(for i <- 0..11, do: for({f, m} <- indexed, i in f, do: m)),
      k: min((@cols - 3) / 2, (@rows - 2) / 2 / @aspect) * :math.sqrt(@d * @d - 1),
      style: List.duplicate(-1, length(edges))
    }
  end

  @impl true
  def frame(state, t, _env) do
    a = 0.6 + t * 0.25
    b = 0.3 + t * 0.15
    ca = :math.cos(a)
    sa = :math.sin(a)
    cb = :math.cos(b)
    sb = :math.sin(b)

    {rs, ss} =
      state.verts
      |> Enum.map(fn {x, y, z} ->
        x1 = x * cb + z * sb
        z1 = -x * sb + z * cb
        r = {x1, y * ca - z1 * sa, y * sa + z1 * ca}
        {_, r1, r2} = r
        f = state.k / (@d - r2)
        # Edges start halfway to the vertex's cell centre, so they meet its mark.
        # The picture sits a little low so opposite vertices change row apart.
        sx = @cols / 2 + f * x1
        sy = @rows / 2 + 0.3 - f * @aspect * r1
        {r, {(sx + floor(sx) + 0.5) / 2, (sy + floor(sy) + 0.5) / 2}}
      end)
      |> Enum.unzip()

    rs = List.to_tuple(rs)
    ss = List.to_tuple(ss)

    # A face is in view when its outward normal (its centre, here) points to the eye.
    seen =
      state.faces
      |> Enum.map(fn f ->
        {cx, cy, cz} =
          Enum.reduce(f, {0, 0, 0}, fn i, {cx, cy, cz} ->
            {x, y, z} = elem(rs, i)
            {cx + x, cy + y, cz + z}
          end)

        if -cx * cx - cy * cy + cz * (3 * @d - cz) > 0, do: 1, else: 0
      end)
      |> List.to_tuple()

    # Visible edges first; hidden ones are dotted and stand clear of them.
    {out, styles} =
      Enum.reduce([1, 0], {%{}, List.to_tuple(state.style)}, fn pass, {out, styles} ->
        out = marks(out, pass, rs, ss, seen, state.vertex_faces)
        lines(out, styles, pass, ss, seen, state.edges)
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, c + r * @cols, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, %{state | style: Tuple.to_list(styles)}}
  end

  defp marks(out, pass, rs, ss, seen, vertex_faces) do
    Enum.reduce(0..11, out, fn i, out ->
      shown = if Enum.any?(elem(vertex_faces, i), &(elem(seen, &1) == 1)), do: 1, else: 0
      {sx, sy} = elem(ss, i)
      c = floor(sx)
      r = floor(sy)

      cond do
        shown != pass -> out
        c < 0 or c >= @cols or r < 0 or r >= @rows -> out
        pass == 0 and not clear?(out, c, r) -> out
        pass == 0 -> Map.put(out, c + r * @cols, "+")
        true -> Map.put(out, c + r * @cols, if(elem(elem(rs, i), 2) > 0.45, do: "@", else: "o"))
      end
    end)
  end

  defp lines(out, styles, pass, ss, seen, edges) do
    edges
    |> Enum.with_index()
    |> Enum.reduce({out, styles}, fn {{i, j, m1, m2}, e}, {out, styles} ->
      if bor(elem(seen, m1), elem(seen, m2)) != pass do
        {out, styles}
      else
        {ax, ay} = elem(ss, i)
        {bx, by} = elem(ss, j)
        {mode, puts} = stroke(ax, ay, bx, by, elem(styles, e))
        {Enum.reduce(puts, out, &put(&2, &1, pass)), put_elem(styles, e, mode)}
      end
    end)
  end

  defp put(out, {c, r, _ch, _k}, _pass) when c < 0 or c >= @cols or r < 0 or r >= @rows, do: out

  defp put(out, {c, r, ch, k}, pass) do
    cond do
      Map.has_key?(out, c + r * @cols) -> out
      pass == 1 or (band(k, 1) == 0 and clear?(out, c, r)) -> Map.put(out, c + r * @cols, ch)
      true -> out
    end
  end

  defp clear?(out, c, r) do
    not Map.has_key?(out, c + r * @cols) and (c == 0 or not Map.has_key?(out, c - 1 + r * @cols)) and
      (c == @cols - 1 or not Map.has_key?(out, c + 1 + r * @cols))
  end

  # Draws a to b (cells: x across, y down) one glyph per column when shallow and
  # one per row when steep, each glyph picked from where the line crosses its
  # cell, so a run reads as one stroke. Returns the style used and the glyphs
  # as {col, row, glyph, step}, step counting along the line in screen cells.
  defp stroke(ax, ay, bx, by, mode) when bx < ax, do: stroke(bx, by, ax, ay, mode)

  defp stroke(ax, ay, bx, by, mode) do
    dx = bx - ax
    dy = by - ay

    if dx < 1.0e-6 and abs(dy) < 1.0e-6 do
      {mode, []}
    else
      mode = style(abs(dy) / max(dx, 1.0e-6), mode)
      {mode, glyphs(mode, ax, ay, bx, by, dx, dy)}
    end
  end

  defp style(q, mode) do
    lo = if mode >= 1, do: elem(@limits, mode - 1), else: 0
    hi = if mode in 0..3, do: elem(@limits, mode) * 1.1, else: nil

    if mode >= 0 and q > lo / 1.1 and (hi == nil or q < hi),
      do: mode,
      else: Enum.count(Tuple.to_list(@limits), &(q >= &1))
  end

  # Quarter or half row heights: _ at the foot of a cell, . low, - middle, ' high.
  defp glyphs(mode, ax, ay, bx, _by, dx, dy) when mode < 2 do
    n = if mode == 1, do: 4, else: 2

    g =
      if mode == 1,
        do: {"_", if(dy > 0, do: "`", else: "'"), "-", ".", "_"},
        else: {"_", "-", "_"}

    for c <- ceil(ax - 0.5)..floor(bx - 0.5)//1 do
      y = ay + dy * (c + 0.5 - ax) / dx
      r = floor(y)
      i = JSMath.round((y - r) * n)
      {c, if(i != 0, do: r, else: r - 1), elem(g, i), c}
    end
  end

  # Corner to corner: _ where the line holds its row, / or \ where it changes.
  defp glyphs(2, ax, ay, bx, _by, dx, dy) do
    for x <- JSMath.round(ax)..(JSMath.round(bx) - 1)//1 do
      ya = JSMath.round(ay + dy * (x - ax) / dx)
      yb = JSMath.round(ay + dy * (x + 1 - ax) / dx)

      cond do
        yb > ya -> {x, ya, "\\", x}
        yb < ya -> {x, ya - 1, "/", x}
        true -> {x, ya - 1, "_", x}
      end
    end
  end

  defp glyphs(mode, ax, ay, _bx, by, dx, dy) do
    ch =
      cond do
        mode == 4 -> "|"
        dy < 0 -> "/"
        true -> "\\"
      end

    for r <- ceil(min(ay, by) - 0.5)..floor(max(ay, by) - 0.5)//1 do
      {floor(ax + dx * (r + 0.5 - ay) / dy), r, ch, r}
    end
  end
end
