defmodule Ascii.Pieces.Chladni do
  @moduledoc """
  Sand travelling to the nodal lines of a ringing plate.

  Sand on a square plate ringing in one of its modes. It lies on the lines
  where two crossed standing waves cancel; when the tone moves on, the grains
  are shaken loose and travel to the lines of the next figure.

  Each mode is cos(n pi x) cos(m pi y) + sign cos(m pi x) cos(n pi y). With n
  and m both odd every figure is mirrored both ways.

  Ported from `src/pieces/chladni.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}

  @meta %Ascii.Meta{
    name: "chladni plate",
    category: :physics,
    note: "sand travelling to the nodal lines of a ringing plate",
    cols: 45,
    rows: 23,
    fps: 12,
    loop: 40
  }

  @modes {{1, 3, -1}, {1, 5, -1}, {3, 5, -1}, {3, 7, -1}, {5, 7, -1}, {3, 7, 1}, {3, 5, 1},
          {1, 5, 1}}
  @count tuple_size(@modes)
  # Seconds the sand takes to find the next figure, and seconds a figure rests.
  @move 2.8
  @hold 2.2
  @grains 1000
  # Share of the sand lying just off the lines.
  @loose 0.1
  @p :math.pi()

  # The plate inside its rim, about square.
  @ic 45 - 2
  @ir 23 - 2
  @n @ic * @ir

  @impl true
  def meta, do: @meta

  # One mode at (x, y) on a 1 by 1 plate, and its slope each way.
  defp wave({n, m, s}, x, y) do
    a = :math.cos(n * @p * x)
    b = :math.cos(m * @p * y)
    c = :math.cos(m * @p * x)
    d = :math.cos(n * @p * y)

    {a * b + s * c * d, -@p * (n * :math.sin(n * @p * x) * b + s * m * :math.sin(m * @p * x) * d),
     -@p * (m * a * :math.sin(m * @p * y) + s * n * c * :math.sin(n * @p * y))}
  end

  # The mode's value alone, the first of wave/3.
  defp value({n, m, s}, x, y) do
    a = :math.cos(n * @p * x)
    b = :math.cos(m * @p * y)
    c = :math.cos(m * @p * x)
    d = :math.cos(n * @p * y)
    a * b + s * c * d
  end

  @impl true
  def init(_options) do
    figs = for mode <- Tuple.to_list(@modes), do: figure(mode)

    # Where the sand lies on each figure, in cells: spread evenly along its
    # lines, a little loose beside them.
    {rest, rnd} = Enum.map_reduce(figs, Int32.to_int32(18), &rest/2)
    rest = List.to_tuple(rest)

    # For each change of figure, which resting place each grain makes for: the
    # nearest one still free, taken in a shuffled order, and when it sets off.
    {trips, _} =
      Enum.map_reduce(0..(@count - 1), rnd, fn k, rnd ->
        trip(k, elem(rest, rem(k + @count - 1, @count)), elem(rest, k), rnd)
      end)

    %{
      marks: figs |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
      trips: List.to_tuple(trips),
      start: 4 * (@move + @hold) - 0.2
    }
  end

  # A mode's figure: a mark in every cell a line is drawn through. A steep line
  # is drawn once a row, in the cell nearer to where it crosses between two
  # cell centres, and a flat one once a column; "+" where two lines cross, "*"
  # where the diagonals cross as well.
  defp figure(mode) do
    {v, ex, ey} =
      for i <- 0..(@n - 1), reduce: {[], [], []} do
        {vs, exs, eys} ->
          {v, fx, fy} = wave(mode, (rem(i, @ic) + 0.5) / @ic, (div(i, @ic) + 0.5) / @ir)
          # The slope per em each way: a column is 0.6em, a row 1.2em.
          v = if abs(v) < 1.0e-9, do: 0, else: v
          {[v | vs], [fx / @ic / 0.6 | exs], [fy / @ir / 1.2 | eys]}
      end

    v = v |> Enum.reverse() |> List.to_tuple()
    ex = ex |> Enum.reverse() |> List.to_tuple()
    ey = ey |> Enum.reverse() |> List.to_tuple()
    f = %{mode: mode, v: v, ex: ex, ey: ey, marks: %{}, at: %{}}

    f = Enum.reduce(0..(@n - 1), f, &trace/2)

    # Near upright, a bracket where the line bows against its crossings in the
    # rows above and below.
    marks =
      Map.new(f.marks, fn
        {i, "|"} -> {i, bracket(f.at, i)}
        other -> other
      end)

    {List.to_tuple(for(i <- 0..(@n - 1), do: Map.get(marks, i, ""))), ex, ey}
  end

  defp trace(i, %{v: v, ex: ex, ey: ey} = f) do
    c = rem(i, @ic)
    r = div(i, @ic)
    vi = elem(v, i)

    if vi == 0 do
      # A line through the cell's centre, or two crossing there.
      cond do
        JSMath.hypot(elem(ex, i), elem(ey, i)) < 1.0e-6 ->
          cross = abs(value(f.mode, (c + 0.85) / @ic, (r + 0.85) / @ir)) < 1.0e-6
          put_mark(f, i, if(cross, do: "*", else: "+"))

        abs(elem(ex, i)) >= abs(elem(ey, i)) ->
          steep(f, i, c + 0.5)

        true ->
          flat(f, i, 0)
      end
    else
      f
      |> across(i, c, vi)
      |> down(i, r, vi)
    end
  end

  defp across(%{v: v, ex: ex, ey: ey} = f, i, c, vi) do
    j = i + 1

    if c < @ic - 1 and vi * elem(v, j) < 0 and
         abs(elem(ex, i) + elem(ex, j)) >= 0.8 * abs(elem(ey, i) + elem(ey, j)) do
      u = vi / (vi - elem(v, j))
      steep(f, if(u < 0.5, do: i, else: j), c + 0.5 + u)
    else
      f
    end
  end

  defp down(%{v: v, ex: ex, ey: ey} = f, i, r, vi) do
    k = i + @ic

    if r < @ir - 1 and vi * elem(v, k) < 0 and
         abs(elem(ey, i) + elem(ey, k)) >= 0.8 * abs(elem(ex, i) + elem(ex, k)) do
      u = vi / (vi - elem(v, k))
      if u < 0.5, do: flat(f, i, u), else: flat(f, k, u - 1)
    else
      f
    end
  end

  defp put_mark(f, i, mark), do: %{f | marks: Map.put(f.marks, i, mark)}

  defp slant(f, i), do: if(elem(f.ex, i) * elem(f.ey, i) > 0, do: "/", else: "\\")

  defp steep(f, i, x) do
    mark = if abs(elem(f.ey, i)) > 0.4 * abs(elem(f.ex, i)), do: slant(f, i), else: "|"
    %{put_mark(f, i, mark) | at: Map.put(f.at, i, x)}
  end

  defp flat(f, i, oy) do
    if Map.has_key?(f.marks, i) do
      f
    else
      put_mark(f, i, flat_mark(f, i, oy))
    end
  end

  defp flat_mark(f, i, oy) do
    cond do
      abs(elem(f.ex, i)) > 0.7 * abs(elem(f.ey, i)) -> slant(f, i)
      oy < -0.22 -> "'"
      oy < 0.14 -> "-"
      oy < 0.34 -> "."
      true -> "_"
    end
  end

  # Upstream marks "no crossing" with NaN, which turns the bow into NaN and
  # leaves the mark upright; here a missing crossing does the same.
  defp bracket(at, i) do
    x = Map.fetch!(at, i)
    r = div(i, @ic)

    with above when above != nil <- near(at, r - 1, x),
         below when below != nil <- near(at, r + 1, x) do
      bow = x - (above + below) / 2

      cond do
        bow > 0.2 -> ")"
        bow < -0.2 -> "("
        true -> "|"
      end
    else
      _ -> "|"
    end
  end

  defp near(_at, r, _x) when r < 0 or r >= @ir, do: nil

  defp near(at, r, x) do
    f = JSMath.floor(x)

    Enum.find_value((f - 1)..(f + 1), fn c ->
      if c >= 0 and c < @ic, do: Map.get(at, r * @ic + c)
    end)
  end

  defp rest({marks, ex, ey}, rnd) do
    on = for i <- 0..(@n - 1), elem(marks, i) != "", do: i
    {on, rnd} = shuffle(on, rnd)
    count = tuple_size(on)

    {xy, rnd} =
      Enum.map_reduce(0..(@grains - 1), rnd, fn g, rnd ->
        {loose, rnd} = Int32.mulberry32(rnd)
        loose = loose < @loose

        {i, rnd} =
          if loose do
            {x, rnd} = Int32.mulberry32(rnd)
            {elem(on, JSMath.floor(x * count)), rnd}
          else
            {elem(on, rem(g, count)), rnd}
          end

        {c, r, rnd} =
          if loose,
            do: off_line(rem(i, @ic), div(i, @ic), elem(ex, i), elem(ey, i), rnd),
            else: {rem(i, @ic), div(i, @ic), rnd}

        {x, rnd} = Int32.mulberry32(rnd)
        {y, rnd} = Int32.mulberry32(rnd)
        {{c + 0.15 + 0.7 * x, r + 0.15 + 0.7 * y}, rnd}
      end)

    {List.to_tuple(xy), rnd}
  end

  # One cell off the line, across it.
  defp off_line(c, r, ex, ey, rnd) do
    {x, rnd} = Int32.mulberry32(rnd)
    side = if x < 0.5, do: -1, else: 1
    {c, r} = if abs(ex) >= abs(ey), do: {c + side, r}, else: {c, r + side}

    {c, r} =
      if abs(ex) > 0.4 * abs(ey) and abs(ey) > 0.4 * abs(ex),
        do: {c + side, r - side * JSMath.sign(ex * ey)},
        else: {c, r}

    {min(@ic - 1, max(0, c)), min(@ir - 1, max(0, r)), rnd}
  end

  # Fisher-Yates from the end, as upstream: a tuple, and the generator after it.
  defp shuffle(list, rnd) do
    tuple = List.to_tuple(list)

    Enum.reduce((tuple_size(tuple) - 1)..1//-1, {tuple, rnd}, fn i, {t, rnd} ->
      {x, rnd} = Int32.mulberry32(rnd)
      j = JSMath.floor(x * (i + 1))
      {t |> put_elem(i, elem(t, j)) |> put_elem(j, elem(t, i)), rnd}
    end)
  end

  defp trip(k, a, b, rnd) do
    {order, rnd} = shuffle(Enum.to_list(0..(@grains - 1)), rnd)
    free = for h <- 0..(@grains - 1), do: {h, elem(b, h)}

    {to, _} =
      Enum.reduce(Tuple.to_list(order), {%{}, free}, fn g, {to, free} ->
        {ax, ay} = elem(a, g)
        best = nearest(free, ax, ay, nil, nil)
        {Map.put(to, g, best), List.keydelete(free, best, 0)}
      end)

    mode = elem(@modes, k)

    # Sand where the new tone shakes hardest leaves first; a grain already on a
    # line barely stirs.
    {grains, rnd} =
      Enum.map_reduce(0..(@grains - 1), rnd, fn g, rnd ->
        {x0, y0} = elem(a, g)
        {x1, y1} = elem(b, Map.fetch!(to, g))
        shake = min(1, abs(value(mode, x0 / @ic, y0 / @ir)) / 0.9)
        len = JSMath.hypot((x1 - x0) * 0.6, (y1 - y0) * 1.2)
        {x, rnd} = Int32.mulberry32(rnd)
        delay = 0.15 + 0.8 * (1 - shake) + 0.3 * x

        {span, rnd} =
          if len < 0.8 do
            {1.0e-6, rnd}
          else
            {x, rnd} = Int32.mulberry32(rnd)
            {min(@move - 0.2 - delay, 0.35 + 0.16 * len + 0.2 * x), rnd}
          end

        {x, rnd} = Int32.mulberry32(rnd)
        {grain(x0, y0, x1, y1, delay, span, (x - 0.5) * 1.6), rnd}
      end)

    {List.to_tuple(grains), rnd}
  end

  # The nearest free resting place, the first of equals.
  defp nearest([], _ax, _ay, _bd, best), do: best

  defp nearest([{h, {bx, by}} | free], ax, ay, bd, best) do
    dx = (bx - ax) * 0.6
    dy = (by - ay) * 1.2
    d = dx * dx + dy * dy

    if bd == nil or d < bd,
      do: nearest(free, ax, ay, d, h),
      else: nearest(free, ax, ay, bd, best)
  end

  # What the frame needs of a grain's hop, in upstream's terms, with the cell
  # it lies in before and after.
  defp grain(x0, y0, x1, y1, delay, span, sway) do
    dx = x1 - x0
    dy = y1 - y0
    len = JSMath.hypot(dx, dy) + 1.0e-9

    g = %{
      delay: delay,
      span: span,
      sway: sway,
      x0: x0,
      y0: y0,
      dx: dx,
      dy: dy,
      dyl: dy / len,
      dxl: dx / len,
      reach: min(1, len / 3)
    }

    Map.merge(g, %{lying: cell(g, 0), landed: cell(g, 1)})
  end

  # Thrown a little off the straight way while it hops, landing true.
  defp cell(g, u) do
    e = u * u * (3 - 2 * u)
    s = g.sway * :math.sin(@p * e) * g.reach
    x = g.x0 + g.dx * e - g.dyl * s * 0.5
    y = g.y0 + g.dy * e + g.dxl * s * 0.25
    c = min(@ic - 1, max(0, JSMath.floor(x)))
    r = min(@ir - 1, max(0, JSMath.floor(y)))
    r * @ic + c
  end

  @impl true
  def frame(%{marks: marks, trips: trips, start: start} = state, t, _env) do
    tt = start + t
    cycle = @move + @hold
    n = JSMath.floor(tt / cycle)
    tau = tt - n * cycle
    k = rem(n, @count)

    # Grains in each cell: still lying where they were, landed, or in the air.
    counts =
      trips
      |> elem(k)
      |> Tuple.to_list()
      |> Enum.reduce(%{}, fn g, counts ->
        u = min(1, max(0, (tau - g.delay) / g.span))

        cond do
          u == 0 -> bump(counts, g.lying, 1)
          u == 1 -> bump(counts, g.landed, 2)
          true -> bump(counts, cell(g, u), 0)
        end
      end)

    was = elem(marks, rem(k + @count - 1, @count))
    is = elem(marks, k)
    rim = String.duplicate("─", @ic)

    rows =
      for r <- 0..(@ir - 1) do
        cells =
          for c <- 0..(@ic - 1) do
            i = r * @ic + c
            glyph(Map.get(counts, i, {0, 0, 0}), elem(is, i), elem(was, i))
          end

        ["│", cells, "│"]
      end

    {Enum.intersperse([["┌", rim, "┐"] | rows] ++ [["└", rim, "┘"]], ?\n), nil, state}
  end

  # {all, lying, landed}, bumped for a grain of kind 1 (lying), 2 (landed) or
  # 0 (in the air).
  defp bump(counts, i, kind) do
    Map.update(counts, i, bump({0, 0, 0}, kind), &bump(&1, kind))
  end

  defp bump({q, lying, landed}, 0), do: {q + 1, lying, landed}
  defp bump({q, lying, landed}, 1), do: {q + 1, lying + 1, landed}
  defp bump({q, lying, landed}, 2), do: {q + 1, lying, landed + 1}

  defp glyph({_, _, landed}, is, _was) when landed > 0 and is != "", do: is
  defp glyph({_, lying, _}, _is, was) when lying > 0 and was != "", do: was
  defp glyph({0, _, _}, _is, _was), do: " "
  defp glyph({q, _, _}, _is, _was) when q < 3, do: "·"
  defp glyph(_counts, _is, _was), do: ":"
end
