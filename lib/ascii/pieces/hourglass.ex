defmodule Ascii.Pieces.Hourglass do
  @moduledoc """
  Sand running through the neck, then turned over.

  An hourglass on its stand. Sand runs through the neck a grain at a time, a
  crater opening above and a heap rising below; when the top runs dry it is
  lifted, turned over on its side and set down the other way up.

  Ported from `src/pieces/hourglass.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}

  @meta %Ascii.Meta{
    name: "hourglass",
    category: :objects,
    note: "sand running through the neck, then turned over",
    cols: 43,
    rows: 21,
    fps: 30
  }

  @cols 43
  @rows 21
  @n 43 * 21
  # A cell in em; lengths are in em.
  @cw 0.6
  @ch 1.2
  # A bulb's length, neck to cap.
  @l 9
  # The glass's half width at the neck, at its widest, at the cap.
  @rn 0.36
  @rm 5.0
  @rc 4.3
  # The posts, out from the middle.
  @px 6
  # The slope sand comes to rest at.
  @k 0.6
  # How high the sand stands when it is all on top.
  @lt 6.2
  # Seconds for the top to run dry, and a pause.
  @run 10.5
  @hold 1.2
  # The turn: lifted, on its side, the other way up, each for so many seconds.
  @turn {0.2, 0.45, 0.2}
  @cycle 10.5 + 1.2 + 0.2 + 0.45 + 0.2
  # A third of the way through, sand in both bulbs.
  @start 3.5
  # Between grains through the neck.
  @dt 0.045
  # Eight looks into each cell, four in its upper half and four in its lower:
  # {across, down} for the upper ones; the lower ones are the same across.
  @across [0.3, 0.7]
  @downs [0.12, 0.38, 0.62, 0.88]

  @cx 43 / 2 * 0.6
  @cy 21 / 2 * 1.2
  @mid div(43, 2)

  @impl true
  def meta, do: @meta

  # The glass's half width at a distance u from the neck: a narrow throat, a
  # full bulb, rounded in to the cap.
  defp w(u) do
    s = min(1, abs(u) / @l)

    if s < 0.76 do
      @rn + (@rm - @rn) * :math.pow(:math.sin(:math.pi() / 2 * (s / 0.76)), 1.5)
    else
      q = (s - 0.76) / 0.24
      @rm - (@rm - @rc) * (q * q)
    end
  end

  defp hash(n) do
    h = Int32.imul(Int32.bxor(n, 0x2C1B3C6D), 0x297A2D39)
    h = Int32.imul(Int32.bxor(h, Int32.ushr(h, 15)), 0x85EBCA77)
    Int32.ushr(Int32.bxor(h, Int32.ushr(h, 13)), 0) / 4_294_967_296
  end

  defp clamp(v), do: min(1, max(0, v))

  defp solve(fun, want, a, b) do
    {a, b} =
      Enum.reduce(1..30, {a, b}, fn _, {a, b} ->
        m = (a + b) / 2
        if fun.(m) < want, do: {m, b}, else: {a, m}
      end)

    (a + b) / 2
  end

  defp steps(from, to, step), do: Stream.iterate(from, &(&1 + step)) |> Enum.take_while(to)

  @impl true
  def init(_options) do
    # One bulb column by column, {v, lo, hi}: how far from the neck its
    # inside runs, so sand can be weighed.
    widths = for u <- steps(0, &(&1 <= @l), 0.02), do: {u, w(u) - 0.15}

    bulb =
      for v <- steps(-@rm + 0.05, &(&1 < @rm), 0.1),
          {lo, hi} = bulb_column(v, widths),
          hi > lo,
          do: {v, lo, hi}

    area = fn fun -> Enum.reduce(bulb, 0, fn {v, lo, hi}, a -> a + fun.(v, lo, hi) end) end

    # On top, a flat level with a crater whose floor is at c; below, a heap
    # whose peak is p up from the floor.
    top_area = fn c ->
      area.(fn v, lo, hi -> max(0, min(min(hi, @lt), c + @k * abs(v)) - lo) end)
    end

    heap_area = fn p ->
      area.(fn v, lo, hi -> max(0, hi - max(lo, @l - p + @k * abs(v))) end)
    end

    all = top_area.(@lt)

    crater = for i <- 0..50, do: solve(top_area, i / 50 * all, -@k * @rm - 1, @lt)
    heap = for i <- 0..50, do: solve(heap_area, i / 50 * all, 0, @l + @k * @rm)

    # On its side, the sand slumps against the lower wall of its bulb.
    side =
      solve(
        fn lv -> area.(fn v, lo, hi -> if v > lv, do: hi - lo, else: 0 end) end,
        all,
        @rm,
        -@rm
      )

    walls = for u <- steps(-@l, &(&1 <= @l + 1.0e-9), 0.04), do: {u, w(u)}

    %{
      crater: List.to_tuple(crater),
      heap: List.to_tuple(heap),
      side: side,
      still: {shell(walls, false, 0), shell(walls, false, 1), shell(walls, true, 0)},
      looks: looks()
    }
  end

  defp bulb_column(v, widths) do
    Enum.reduce(widths, {@l, 0}, fn {u, wu}, {lo, hi} ->
      if abs(v) < wu, do: {min(lo, u), u}, else: {lo, hi}
    end)
  end

  # Where each look lands, by row and by column, upright (lifted or not) and
  # on its side: {u or v, and for u, the inside's half width there, or nil
  # past the caps}.
  defp looks do
    cols =
      for c <- 0..(@cols - 1) do
        List.to_tuple(for a <- @across, do: (c + a) * @cw - @cx)
      end
      |> List.to_tuple()

    rows = fn lift ->
      for r <- 0..(@rows - 1) do
        List.to_tuple(for b <- @downs, do: @cy - lift * @ch - (r + b) * @ch)
      end
      |> List.to_tuple()
    end

    inside = fn u -> if abs(u) < @l, do: w(u) - 0.15 end

    %{
      cols: cols,
      rows: {rows.(0), rows.(1)},
      up: {map2(rows.(0), inside), map2(rows.(1), inside)},
      across: map2(cols, inside)
    }
  end

  defp map2(t, fun) do
    t
    |> Tuple.to_list()
    |> Enum.map(&(&1 |> Tuple.to_list() |> Enum.map(fun) |> List.to_tuple()))
    |> List.to_tuple()
  end

  # Draws a line through points as puts {row, col, mark}: one mark a column
  # where it runs flat, set at the height it crosses the cell, and one a row
  # where it runs steep, a bracket where it bows.
  defp trace(pts) do
    {flat, steep} =
      pts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce({[], []}, fn [{x0, y0}, {x1, y1}], {flat, steep} ->
        dx = x1 - x0
        dy = y1 - y0

        flat =
          if abs(dy) <= 1.4 * abs(dx) do
            c0 = floor(min(x0, x1) / @cw - 0.5) + 1
            c1 = floor(max(x0, x1) / @cw - 0.5)

            Enum.reduce(c0..c1//1, flat, fn c, flat ->
              y = (y0 + dy * ((c + 0.5) * @cw - x0) / dx) / @ch
              r = floor(y)
              [{r, c, flat_mark(y - r)} | flat]
            end)
          else
            flat
          end

        steep =
          if abs(dy) >= 0.8 * abs(dx) do
            r0 = floor(min(y0, y1) / @ch - 0.5) + 1
            r1 = floor(max(y0, y1) / @ch - 0.5)

            Enum.reduce(r0..r1//1, steep, fn r, steep ->
              [{r, x0 + dx * ((r + 0.5) * @ch - y0) / dy, dx / dy} | steep]
            end)
          else
            steep
          end

        {flat, steep}
      end)

    steep = steep |> Enum.reverse() |> List.to_tuple()
    last = tuple_size(steep) - 1

    steep_puts =
      for i <- 0..last//1 do
        {r, x, s} = elem(steep, i)
        a = if i > 0, do: elem(steep, i - 1)
        b = if i < last, do: elem(steep, i + 1)
        {r, floor(x / @cw), steep_mark(s, r, x, a, b)}
      end

    Enum.reverse(flat, steep_puts)
  end

  defp flat_mark(f) when f < 0.3, do: "'"
  defp flat_mark(f) when f < 0.6, do: "-"
  defp flat_mark(f) when f < 0.85, do: "."
  defp flat_mark(_f), do: "_"

  defp steep_mark(s, _r, _x, _a, _b) when abs(s) > 0.3, do: if(s > 0, do: "\\", else: "/")

  defp steep_mark(_s, r, x, {ra, xa, _}, {rb, xb, _})
       when abs(ra - r) == 1 and abs(rb - r) == 1 do
    bow = x - (xa + xb) / 2

    cond do
      bow > 0.1 -> ")"
      bow < -0.1 -> "("
      true -> "|"
    end
  end

  defp steep_mark(_s, _r, _x, _a, _b), do: "|"

  defp put(g, r, c, m) when r >= 0 and r < @rows and c >= 0 and c < @cols,
    do: Map.put(g, r * @cols + c, m)

  defp put(g, _r, _c, _m), do: g

  # The glass and stand upright, lifted by `lift` rows, or on its side.
  defp shell(walls, side, lift) do
    at = fn u, v -> if side, do: {@cx + u, @cy + v}, else: {@cx + v, @cy - lift * @ch - u} end

    {g, _by} =
      for sv <- [-1, 1], reduce: {%{}, %{}} do
        acc ->
          walls
          |> Enum.map(fn {u, wu} -> at.(u, sv * wu) end)
          |> trace()
          |> Enum.reduce(acc, &wall_put(&1, &2, sv))
      end

    # The neck's row, upright.
    n0 = JSMath.round(@cy / @ch - 0.5)
    g = if side, do: side_stand(g, n0), else: stand(g, n0, lift)
    List.to_tuple(for i <- 0..(@n - 1), do: Map.get(g, i))
  end

  # Where both walls run flat through one cell, at the neck on its side,
  # they make a "=". Upstream marks the cell by its flat index, even off the
  # side of a row.
  defp wall_put({r, c, m}, {g, by}, sv) do
    i = r * @cols + c
    flat = m in ["'", "-", ".", "_"]
    both = Map.get(by, i, 0) == -sv
    g = put(g, r, c, if(flat and both, do: "=", else: m))
    by = if flat and i >= 0 and i < @n, do: Map.put(by, i, if(both, do: 2, else: sv)), else: by
    {g, by}
  end

  # Plates with turned ends, the posts let into them.
  defp stand(g, n0, lift) do
    pc = JSMath.round(@px / @cw)
    top = n0 - lift - 8
    bot = n0 - lift + 8
    hw = pc + 2

    g =
      Enum.reduce((@mid - hw)..(@mid + hw), g, fn c, g ->
        post = abs(c - @mid) == pc

        {a, b, d, e} =
          cond do
            c == @mid - hw -> {"╒", "╘", "╒", "╘"}
            c == @mid + hw -> {"╕", "╛", "╕", "╛"}
            post -> {"═", "╤", "╧", "═"}
            true -> {"═", "═", "═", "═"}
          end

        g |> put(top - 1, c, a) |> put(top, c, b) |> put(bot, c, d) |> put(bot + 1, c, e)
      end)

    Enum.reduce((top + 1)..(bot - 1)//1, g, fn r, g ->
      g |> put(r, @mid - pc, "│") |> put(r, @mid + pc, "│")
    end)
  end

  # On its side the plates stand up at either end and the posts run across.
  defp side_stand(g, n0) do
    hr = JSMath.round(@px / @ch)
    ends = [@mid - 16, @mid + 16]

    g =
      for {c, k} <- Enum.with_index(ends), r <- (n0 - hr - 1)..(n0 + hr + 1), reduce: g do
        g ->
          post = abs(r - n0) == hr

          {a, b, d} =
            cond do
              r == n0 - hr - 1 ->
                {"╓", "─", "╖"}

              r == n0 + hr + 1 ->
                {"╙", "─", "╜"}

              true ->
                {if(post and k == 1, do: "╢", else: "║"), " ",
                 if(post and k == 0, do: "╟", else: "║")}
            end

          g |> put(r, c - 1, a) |> put(r, c, b) |> put(r, c + 1, d)
      end

    Enum.reduce((hd(ends) + 2)..(List.last(ends) - 2)//1, g, fn c, g ->
      g |> put(n0 - hr, c, "─") |> put(n0 + hr, c, "─")
    end)
  end

  defp table(tab, x) do
    f = clamp(x) * 50
    i = min(49, floor(f))
    elem(tab, i) + (elem(tab, i + 1) - elem(tab, i)) * (f - i)
  end

  @impl true
  def frame(state, t, _env) do
    k = JSMath.mod(JSMath.mod(@start + t, @cycle) + @cycle, @cycle)
    {t0, t1, _} = @turn
    # Into the turn, once it starts.
    turn = k - @run - @hold

    phase =
      cond do
        turn < 0 -> -1
        turn < t0 -> 0
        turn < t0 + t1 -> 1
        true -> 2
      end

    side = phase == 1
    lift = if phase == 0 or phase == 2, do: 1, else: 0
    # The share of sand still on top.
    left = if phase == 2, do: 1, else: clamp(1 - k / @run)

    sand =
      if side,
        do: {:side, state.side},
        else: {:up, table(state.crater, left), table(state.heap, 1 - left)}

    bits = bits(state.looks, side, lift, sand)
    bits = if phase < 0, do: stream(bits, k, -@l + table(state.heap, 1 - left)), else: bits
    glass = elem(state.still, if(side, do: 2, else: lift))

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          i = r * @cols + c
          elem(glass, i) || elem({" ", "'", ".", ":"}, Map.get(bits, i, 0))
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # Sand: a grain in each half cell where most of its looks land in sand.
  defp bits(looks, side, lift, sand) do
    for r <- 0..(@rows - 1), c <- 0..(@cols - 1), reduce: %{} do
      bits ->
        {hi, lo} = cell(looks, side, lift, sand, r, c)
        b = if(hi > 2, do: 1, else: 0) + if(lo > 2, do: 2, else: 0)
        if b == 0, do: bits, else: Map.put(bits, r * @cols + c, b)
    end
  end

  defp cell(looks, side, lift, sand, r, c) do
    xs = elem(looks.cols, c)
    ys = elem(elem(looks.rows, lift), r)

    for bi <- 0..3, ai <- 0..1, reduce: {0, 0} do
      {hi, lo} ->
        x = elem(xs, ai)
        y = elem(ys, bi)

        {u, v, lim} =
          if side,
            do: {x, -y, elem(elem(looks.across, c), ai)},
            else: {y, x, elem(elem(elem(looks.up, lift), r), bi)}

        cond do
          lim == nil or abs(v) >= lim or not sand?(sand, u, v) -> {hi, lo}
          bi < 2 -> {hi + 1, lo}
          true -> {hi, lo + 1}
        end
    end
  end

  defp sand?({:side, level}, u, v), do: u < 0 and v > level
  defp sand?({:up, crater, _heap}, u, v) when u > 0, do: u < min(@lt, crater + @k * abs(v))
  defp sand?({:up, _crater, heap}, u, v), do: @l - -u < heap - @k * abs(v)

  # The stream: grains leave the neck one by one and speed up as they fall
  # onto the heap.
  defp stream(bits, k, peak) do
    first = max(0, JSMath.floor((k - 0.8) / @dt))
    until = min(k, @run)

    Stream.iterate(first, &(&1 + 1))
    |> Enum.take_while(&(&1 * @dt <= until))
    |> Enum.reduce(bits, fn i, bits ->
      a = k - i * @dt - hash(i + 7919) * @dt * 0.7
      u = 0.1 - 3 * a - 18 * a * a

      if hash(i) < 0.18 or a < 0 or u < peak do
        bits
      else
        y = (@cy - u) / @ch
        bit = if JSMath.mod(y, 1) < 0.5, do: 1, else: 2
        Map.update(bits, floor(y) * @cols + @mid, bit, &Bitwise.bor(&1, bit))
      end
    end)
  end
end
