defmodule AsciiArt.Pieces.Tesseract do
  @moduledoc """
  A 4d hypercube turning, its cubes passing through each other.

  A 4D hypercube turning in the xw and yz planes, projected 4D to 3D to 2D.
  All 32 edges are drawn: solid on the side toward the 4D eye, dotted on the
  far side, so the two cubes can be followed as they pass through.

  Ported from `src/pieces/tesseract.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "tesseract",
    category: :shapes,
    note: "a 4d hypercube turning, its cubes passing through each other",
    cols: 54,
    rows: 28,
    fps: 30
  }

  @cols 54
  @rows 28
  # Rows per column at which a line changes style: flat, shallow, diagonal,
  # steep, upright. A slope near a boundary keeps the style it had last frame.
  @limits {0.2, 0.38, 1, 2.1}
  # 4D eye to centre, and 3D eye to centre.
  @w4 3
  @d 7
  @aspect 0.5
  # A quarter turn maps the hypercube onto itself, so the motion repeats
  # after a quarter turn in yz, which is a whole turn in xw.
  @yz 0.0875
  @loop :math.pi() / 2 / @yz

  @verts for i <- 0..15,
             do:
               for(b <- [1, 2, 4, 8], do: if(band(i, b) != 0, do: 1, else: -1)) |> List.to_tuple()
  # Edges join vertices that differ in one coordinate.
  @edges for i <- 0..15, b <- [1, 2, 4, 8], band(i, b) == 0, do: {i, bor(i, b)}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    tilt = {:math.cos(0.5), :math.sin(0.5), :math.cos(0.32), :math.sin(0.32)}

    # Size the picture from the widest it gets over one loop of the motion.
    {ex, ey} =
      0
      |> Stream.iterate(&(&1 + 0.03))
      |> Enum.take_while(&(&1 < @loop))
      |> Enum.reduce({0, 0}, fn t, acc ->
        {_, ps} = view(t, tilt)

        Enum.reduce(ps, acc, fn {px, py}, {ex, ey} ->
          {max(ex, abs(px)), max(ey, abs(py))}
        end)
      end)

    %{
      tilt: tilt,
      k: min((@cols - 2) / 2 / ex, (@rows - 1) / 2 / @aspect / ey),
      style: List.duplicate(-1, length(@edges)),
      # 2 until first decided.
      solid: List.duplicate(2, length(@edges) + 16)
    }
  end

  # 4D point to {x, y, z, w} in camera space, before the screen scale.
  defp place({p0, p1, p2, p3}, ca, sa, cb, sb, {t0, t1, t2, t3}) do
    x = p0 * ca - p3 * sa
    w = p0 * sa + p3 * ca
    y = p1 * cb - p2 * sb
    z = p1 * sb + p2 * cb
    f = @w4 / (@w4 - w)
    bx = x * f
    by = y * f
    bz = z * f
    # A fixed view from up and to the side, so the cubes read as solids.
    x1 = bx * t0 + bz * t1
    z1 = -bx * t1 + bz * t0
    {x1, by * t2 - z1 * t3, by * t3 + z1 * t2, w}
  end

  # Each vertex as seen, before the screen scale, measured from the mean of
  # them all, so the picture stays centred as the near cube swings out.
  defp view(t, tilt) do
    a = 0.4 + t * 4 * @yz
    b = 0.2 + t * @yz
    ca = :math.cos(a)
    sa = :math.sin(a)
    cb = :math.cos(b)
    sb = :math.sin(b)
    rs = Enum.map(@verts, &place(&1, ca, sa, cb, sb, tilt))

    {ps, {mx, my}} =
      Enum.map_reduce(rs, {0, 0}, fn {x, y, z, _}, {mx, my} ->
        px = x / (@d - z)
        py = y / (@d - z)
        {{px, py}, {mx + px / 16, my + py / 16}}
      end)

    {rs, Enum.map(ps, fn {px, py} -> {px - mx, py - my} end)}
  end

  @impl true
  def frame(state, t, _env) do
    {rs, ps} = view(t, state.tilt)

    ss =
      ps
      |> Enum.map(fn {px, py} ->
        # Edges start halfway to the vertex's cell centre, so they meet its mark.
        x = @cols / 2 + state.k * px
        y = @rows / 2 - state.k * @aspect * py
        {(x + floor(x) + 0.5) / 2, (y + floor(y) + 0.5) / 2}
      end)
      |> List.to_tuple()

    ws = rs |> Enum.map(&elem(&1, 3)) |> List.to_tuple()

    # Toward the 4D eye is solid; a band around w = 0 keeps the last choice.
    weights =
      Enum.map(@edges, fn {i, j} -> (elem(ws, i) + elem(ws, j)) / 2 end) ++ Tuple.to_list(ws)

    solid =
      Enum.zip_with(state.solid, weights, fn s, w ->
        if s == 2 or abs(w) > 0.12, do: if(w >= 0, do: 1, else: 0), else: s
      end)

    {edge_solid, vertex_solid} = Enum.split(solid, length(@edges))
    vertex_solid = List.to_tuple(vertex_solid)

    # The solid half first; the dotted half then keeps clear of it.
    {out, styles} =
      Enum.reduce([1, 0], {%{}, List.to_tuple(state.style)}, fn pass, {out, styles} ->
        out = marks(out, pass, ss, vertex_solid)
        lines(out, styles, pass, ss, edge_solid)
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, c + r * @cols, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, %{state | style: Tuple.to_list(styles), solid: solid}}
  end

  defp marks(out, pass, ss, vertex_solid) do
    Enum.reduce(0..15, out, fn i, out ->
      {sx, sy} = elem(ss, i)
      c = floor(sx)
      r = floor(sy)

      cond do
        elem(vertex_solid, i) != pass -> out
        c < 0 or c >= @cols or r < 0 or r >= @rows -> out
        pass == 1 -> Map.put(out, c + r * @cols, "o")
        clear?(out, c, r) -> Map.put(out, c + r * @cols, "+")
        true -> out
      end
    end)
  end

  defp lines(out, styles, pass, ss, edge_solid) do
    @edges
    |> Enum.zip(edge_solid)
    |> Enum.with_index()
    |> Enum.reduce({out, styles}, fn
      {{_, solid}, _e}, acc when solid != pass ->
        acc

      {{{i, j}, _}, e}, {out, styles} ->
        {ax, ay} = elem(ss, i)
        {bx, by} = elem(ss, j)
        {mode, puts} = stroke(ax, ay, bx, by, elem(styles, e))
        {Enum.reduce(puts, out, &put(&2, &1, pass)), put_elem(styles, e, mode)}
    end)
  end

  defp put(out, {c, r, _ch, _k}, _pass) when c < 0 or c >= @cols or r < 0 or r >= @rows, do: out

  defp put(out, {c, r, ch, k}, pass) do
    if not Map.has_key?(out, c + r * @cols) and (pass == 1 or rem(k, 3) != 2),
      do: Map.put(out, c + r * @cols, ch),
      else: out
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
