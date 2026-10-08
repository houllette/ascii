defmodule AsciiArt.Pieces.Fern do
  @moduledoc """
  Barnsley's fern filling in point by point, then swaying.

  Barnsley's fern, grown by the chaos game, its leaflets slimmed a little so
  they stay apart at this size. Each leaflet is drawn along the way its
  points run; the frond fills in from a sparse young one, then sways.

  Up to 36,000 points are placed every frame, each with five trigonometric
  calls, which even with `:math` is nearly three times the frame budget. So
  the frame first places every point approximately, to within about 5e-7 of
  a cell (sin(t * 4 + v0 * 3) by the angle sum from per-point constants, the
  bend's cosine and sine by short series, since the bend never passes about
  0.156), and sums each cell's strokes in fixed point to within 1e-8 a
  stroke. It keeps that answer only where it is certain to be upstream's: a
  point within 1e-5 of a cell's edge is placed again exactly, and a cell
  whose character could change by as much as its sums could be off
  (upstream's sums are a `Float32Array`, rounded at every step) is summed
  again exactly, point by point in upstream's order. `exact_frame/2` is the
  frame worked out exactly throughout, which the tests hold the fast frame
  to.

  Ported from `src/pieces/fern.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}

  @meta %AsciiArt.Meta{
    name: "fern",
    category: :nature,
    note: "barnsley's fern filling in point by point, then swaying",
    cols: 44,
    rows: 30,
    fps: 20
  }

  @cols 44
  @rows 30
  @cells 44 * 30
  # Points when fully grown; seconds from a young frond to a full one;
  # leaflet width against Barnsley's own.
  @n 36_000
  @grow 3
  @slim 0.55
  @tau :math.pi() * 2
  # Barnsley's maps: {a, b, c, d, e, f, cumulative chance}.
  @maps [
    {0.0, 0.0, 0.0, 0.16, 0.0, 0.0, 0.01},
    {0.85, 0.04, -0.04, 0.85, 0.0, 1.6, 0.85},
    {0.2 * @slim, -0.26, 0.23 * @slim, 0.22, 0.0, 1.6, 0.925},
    {-0.15 * @slim, 0.28, 0.26 * @slim, 0.24, 0.0, 0.44, 1}
  ]
  # Centres the frond over its root.
  @shift -0.25
  # Rows per fern unit at full height, and the root.
  @s (30 - 3.8) / 10
  @root_r 30 - 1.5
  @root_c 44 / 2

  # The fast pass: sums in fixed point, 2^30 to one, a cell's count riding
  # in the top bits of its first sum (each term adds 2^@pack, and the sum of
  # the strokes stays far below that); how near a cell's edge a point must
  # be placed again; how far one stroke may be off.
  @fix 1_073_741_824.0
  @pack 47
  @one Bitwise.bsl(1, @pack)
  @edge 1.0e-5
  @term 1.0e-7
  # The series for the bend's cosine and sine, off by at most 2e-8 and 5e-10
  # while it stays under 0.156.
  @c4 1 / 24
  @s3 -1 / 6
  @s5 1 / 120

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    # Every point lies on some leaflet: the copy of the frond the last
    # leaflet map made, carried up the stem by however many steps of the
    # second map followed it. That leaflet's axis is the way the point's
    # stroke runs.
    lean =
      for m <- [0, 2, 3] do
        List.to_tuple(for k <- 0..60, do: axis(k, m))
      end
      |> List.to_tuple()

    {points, _} =
      Enum.reduce(-20..(@n - 1), {[], {0.0, 0.0, 0, 0, Int32.to_int32(17)}}, fn i, {acc, st} ->
        {x, y, k, m, rand} = st
        {p, rand} = Int32.mulberry32(rand)
        j = Enum.find_index(@maps, fn q -> p < elem(q, 6) end)
        {a, b, c, d, e, f, _} = Enum.at(@maps, j)
        {x, y} = {a * x + b * y + e, c * x + d * y + f}
        {k, m} = if j == 1, do: {min(60, k + 1), m}, else: {0, j}
        st = {x, y, k, m, rand}

        if i >= 0 do
          pl = lean |> elem(if(m != 0, do: m - 1, else: 0)) |> elem(k) |> JSMath.fround()
          {[point(JSMath.fround(x + @shift), JSMath.fround(y), pl) | acc], st}
        else
          {acc, st}
        end
      end)

    # The rachis: the stem's foot carried up the frond by the second map, one
    # node a step, to where it closes on the tip.
    {spine, _} =
      Enum.map_reduce(1..60, {0, 0}, fn _, {sx, sy} ->
        sx2 = 0.85 * sx + 0.04 * sy
        sy2 = -0.04 * sx + 0.85 * sy + 1.6
        {{sx2 + @shift, sy2}, {sx2, sy2}}
      end)

    %{points: Enum.reverse(points), spine: [{@shift, 0} | spine]}
  end

  defp axis(k, m) do
    {u, v} = if m == 0, do: {0, 1}, else: {elem(Enum.at(@maps, m), 1), elem(Enum.at(@maps, m), 3)}

    {u, v} =
      Enum.reduce(1..k//1, {u, v}, fn _, {u, v} -> {0.85 * u + 0.04 * v, -0.04 * u + 0.85 * v} end)

    # From upright, rightward positive.
    :math.atan2(u, v)
  end

  # What a point keeps between frames: where it is, the way its stroke runs,
  # and for the fast pass the parts of its bend that do not change and its
  # stroke while it stands still, in fixed point.
  defp point(u0, v0, pl) do
    h = v0 / 10
    c2 = :math.cos(2 * pl)
    s2 = :math.sin(2 * pl)

    {u0, v0, -u0, h, h * :math.sqrt(h) * 1.6, :math.cos(v0 * 3), :math.sin(v0 * 3), pl, c2, s2,
     trunc(c2 * @fix), trunc(s2 * @fix)}
  end

  # Growth: a sparse young frond that rises to full height as its points
  # arrive. The sway comes in as the growth ends; the frond bends more the
  # higher up it is.
  defp params(t) do
    g = min(1, t / @grow)
    e = g * g * (3 - 2 * g)
    calm = min(1, max(0, (t - @grow * 0.5) / @grow))

    %{
      n: floor(@n * (0.05 + 0.95 * e)),
      scale: @s * (0.8 + 0.2 * e),
      sway: calm * (0.07 * :math.sin(@tau * t / 5) + 0.02 * :math.sin(@tau * t / 2 + 1)),
      calm012: 0.012 * calm,
      t4: t * 4,
      t: t
    }
  end

  defp bend(v0, fr) do
    h = v0 / 10
    fr.sway * h * :math.sqrt(h) * 1.6 + fr.calm012 * h * :math.sin(fr.t4 + v0 * 3)
  end

  defp place(u0, v0, fr) do
    a = bend(v0, fr)
    ca = :math.cos(a)
    sa = :math.sin(a)
    {@root_c + (u0 * ca + v0 * sa) * 2 * fr.scale, @root_r - (-u0 * sa + v0 * ca) * fr.scale}
  end

  @impl true
  def frame(state, t, _env) do
    fr = params(t)
    # The cells' counts and sums, in fixed point; and each point's cell, the
    # last first.
    acc = :atomics.new(2 * @cells, signed: true)

    ks =
      cond do
        # Without a bend there is nothing to approximate.
        fr.sway == 0 and fr.calm012 == 0 ->
          still(state.points, fr.n, fr, acc, [])

        # Past years of play t * 4 + v0 * 3 rounds by more than the margins.
        fr.t4 > 1.0e9 ->
          :exact

        true ->
          gather(
            state.points,
            fr.n,
            fr.sway,
            fr.calm012,
            {:math.sin(fr.t4), :math.cos(fr.t4)},
            fr.scale,
            fr,
            acc,
            []
          )
      end

    if ks == :exact,
      do: {exact_frame(state, t), nil, state},
      else: {fast_frame(state, fr, acc, ks), nil, state}
  end

  defp fast_frame(state, fr, acc, ks) do
    full = 0.6 + 0.4 * :math.sqrt(fr.n / @n)

    # Each cell takes the way its leaflets run: a slash along a slanting
    # one, a bar along an upright one, a dash where one lies flat. A thin
    # scatter, or leaflets crossing, is a dot.
    out =
      for k <- 0..(@cells - 1) do
        packed = :atomics.get(acc, 2 * k + 1)
        n0 = Bitwise.bsr(packed + Bitwise.bsl(1, @pack - 1), @pack)
        sc = (packed - Bitwise.bsl(n0, @pack)) / @fix
        ss = :atomics.get(acc, 2 * k + 2) / @fix
        quick(n0, sc, ss, full)
      end

    unsure = for {:unsure, k} <- Enum.with_index(out), into: MapSet.new(), do: k

    out =
      if MapSet.size(unsure) == 0 do
        out
      else
        points = Enum.take(state.points, fr.n)
        sums = exact_sums(points, Enum.reverse(ks), unsure, fr)

        out
        |> Enum.with_index()
        |> Enum.map(fn
          {:unsure, k} -> stroke(Map.fetch!(sums, k), full)
          {ch, _} -> ch
        end)
      end

    draw(out, state.spine, fr)
  end

  @doc false
  # The frame worked out the slow way, every point with `AsciiArt.JSMath`:
  # what the fast pass in `frame/3` must always agree with.
  @spec exact_frame(state :: map(), t :: float()) :: iodata()
  def exact_frame(state, t) do
    fr = params(t)
    points = Enum.take(state.points, fr.n)
    ks = Enum.map(points, fn p -> exact_cell(elem(p, 0), elem(p, 1), fr) end)
    sums = exact_sums(points, ks, nil, fr)
    full = 0.6 + 0.4 * :math.sqrt(fr.n / @n)
    out = for k <- 0..(@cells - 1), do: stroke(Map.get(sums, k, {0, 0.0, 0.0}), full)
    draw(out, state.spine, fr)
  end

  # Each point, placed approximately. Its cell is certain unless it lies
  # within @edge of a cell's edge, where it is placed again exactly. Its
  # stroke is added to the cell's sums in fixed point.
  defp gather([], _left, _sway, _c012, _t4, _scale, _fr, _acc, ks), do: ks
  defp gather(_points, 0, _sway, _c012, _t4, _scale, _fr, _acc, ks), do: ks

  defp gather([p | rest], left, sway, c012, {st4, ct4} = t4, scale, fr, acc, ks) do
    {u0, v0, nu0, h, hsh, cv3, sv3, _pl, c2, s2, _, _} = p
    # sin(t * 4 + v0 * 3), and the bend's cosine and sine by their series:
    # the bend is never more than about 0.156.
    bend = sway * hsh + c012 * h * (st4 * cv3 + ct4 * sv3)
    z = bend * bend
    ca = 1.0 + z * (-0.5 + z * @c4)
    sa = bend * (1.0 + z * (@s3 + z * @s5))
    x = @root_c + (u0 * ca + v0 * sa) * 2.0 * scale
    y = @root_r - (nu0 * sa + v0 * ca) * scale
    k = locate(x, y, u0, v0, fr)

    if k >= 0 do
      # The stroke at twice the leaflet's angle and the bend's.
      cb = 1.0 - 2.0 * sa * sa
      sb = 2.0 * sa * ca
      :atomics.add(acc, 2 * k + 1, trunc((c2 * cb - s2 * sb) * @fix) + @one)
      :atomics.add(acc, 2 * k + 2, trunc((s2 * cb + c2 * sb) * @fix))
    end

    gather(rest, left - 1, sway, c012, t4, scale, fr, acc, [k | ks])
  end

  # The same while the frond stands still (no bend at all), each stroke
  # worked out once.
  defp still([], _left, _fr, _acc, ks), do: ks
  defp still(_points, 0, _fr, _acc, ks), do: ks

  defp still([{u0, v0, _, _, _, _, _, _, _, _, co, si} | rest], left, fr, acc, ks) do
    k = locate(@root_c + u0 * 2 * fr.scale, @root_r - v0 * fr.scale, u0, v0, fr)

    if k >= 0 do
      :atomics.add(acc, 2 * k + 1, co + @one)
      :atomics.add(acc, 2 * k + 2, si)
    end

    still(rest, left - 1, fr, acc, [k | ks])
  end

  # A point's cell, placed again exactly when it lies near an edge.
  @compile {:inline, locate: 5}
  defp locate(x, y, u0, v0, fr) do
    c = floor(x)
    r = floor(y)
    fx = x - c
    fy = y - r

    if fx < @edge or fx > 1.0 - @edge or fy < @edge or fy > 1.0 - @edge,
      do: exact_cell(u0, v0, fr),
      else: cell(c, r)
  end

  defp exact_cell(u0, v0, fr) do
    {x, y} = place(u0, v0, fr)
    cell(floor(x), floor(y))
  end

  defp cell(c, r) when c < 0 or c >= @cols or r < 0 or r >= @rows, do: -1
  defp cell(c, r), do: c + r * @cols

  # A cell's character from the fast sums, or :unsure where the rounding in
  # them could reach a threshold. Each sum is off from upstream's by at most
  # `bound`: single-precision rounding at every step (upstream's sums are a
  # Float32Array), and the terms' own error.
  defp quick(n0, _sc, _ss, full) when n0 < 2 * full, do: " "
  defp quick(n0, _sc, _ss, full) when n0 < 6 * full, do: "."

  defp quick(n0, sc, ss, _full) do
    bound = n0 * ((n0 + 1) * 6.0e-8 + @term)
    e = 1.5 * bound + 1.0e-12
    hyp = :math.sqrt(sc * sc + ss * ss)
    half = 0.5 * n0

    cond do
      hyp + e < half ->
        "."

      hyp - e <= half ->
        :unsure

      true ->
        a = 0.5 * :math.atan2(ss, sc)
        err = e / (hyp - e) + 1.0e-12
        if near?(abs(a), 0.33, err) or near?(abs(a), 1.25, err), do: :unsure, else: glyph(a)
    end
  end

  defp near?(v, at, err), do: abs(v - at) <= err

  # Upstream's sums for the cells asked for (all with nil), point by point in
  # order, each stroke exact and each sum rounded to single precision.
  defp exact_sums(points, ks, cells, fr) do
    Enum.zip_reduce(points, ks, %{}, fn p, k, sums ->
      v0 = elem(p, 1)
      pl = elem(p, 7)

      if k >= 0 and (cells == nil or MapSet.member?(cells, k)) do
        a = 2 * (pl + bend(v0, fr))
        {n0, sc, ss} = Map.get(sums, k, {0, 0.0, 0.0})

        Map.put(
          sums,
          k,
          {n0 + 1, JSMath.fround(sc + :math.cos(a)), JSMath.fround(ss + :math.sin(a))}
        )
      else
        sums
      end
    end)
  end

  defp stroke({n0, _sc, _ss}, full) when n0 < 2 * full, do: " "

  defp stroke({n0, sc, ss}, full) do
    a = 0.5 * :math.atan2(ss, sc)
    sure = JSMath.hypot(ss, sc) / n0
    if n0 < 6 * full or sure < 0.5, do: ".", else: glyph(a)
  end

  defp glyph(a) do
    cond do
      abs(a) < 0.33 -> "|"
      abs(a) > 1.25 -> "-"
      a > 0 -> "/"
      true -> "\\"
    end
  end

  defp draw(out, spine, fr) do
    out = List.to_tuple(out)

    # The rachis, one cell a row from the root to the tip, curving over.
    pts = Enum.map(spine, fn {u0, v0} -> place(u0, v0, fr) end)

    over =
      pts
      |> Enum.zip(tl(pts))
      |> Enum.reduce(%{}, fn {{x0, y0}, {x1, y1}}, over ->
        s = (x1 - x0) / (y0 - y1 + 1.0e-9)

        ch =
          cond do
            s < 0.4 -> "|"
            s < 1.4 -> "("
            true -> "/"
          end

        for r <- ceil(y1 - 0.5)..floor(y0 - 0.5)//1,
            c = floor(x0 + s * (y0 - r - 0.5)),
            c >= 0 and c < @cols and r >= 0 and r < @rows,
            reduce: over do
          over -> Map.put(over, c + r * @cols, ch)
        end
      end)

    # A little soil round the root.
    {x_root, _} = hd(pts)
    rc = floor(x_root)

    over =
      for c <- (rc - 6)..(rc + 6),
          i = c + (@rows - 1) * @cols,
          i >= 0 and i < @cells and Map.get(over, i, elem(out, i)) == " ",
          reduce: over do
        over -> Map.put(over, i, if(abs(c - rc) > 4, do: ".", else: "_"))
      end

    for r <- 0..(@rows - 1) do
      for c <- 0..(@cols - 1), i = c + r * @cols, do: Map.get(over, i, elem(out, i))
    end
    |> Enum.intersperse(?\n)
  end
end
