defmodule AsciiArt.Pieces.Fireworks do
  @moduledoc """
  Shells climb and burst as peonies, rings, willows and palms.

  Shells climb on a sparkling trail and burst. Every spark follows a
  closed-form path under air drag and gravity, so any moment can be drawn
  straight from the clock, and each shell is one of several kinds of burst.

  Ported from `src/pieces/fireworks.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.Int32
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "fireworks",
    category: :effects,
    note: "shells climb and burst as peonies, rings, willows and palms",
    cols: 64,
    rows: 24,
    fps: 30
  }

  @cols 64
  @rows 24
  # Sky height in column widths.
  @sky @rows * 2
  # Gravity, in column widths a second squared (a row is two).
  @g 13
  # Seconds between launches.
  @every 1.25
  # Shells take their kind and their spot on the skyline in turn.
  @kinds {:peony, :willow, :ring, :palm, :saturn, :peony, :willow, :ring, :palm}
  @spots {0.3, 0.68, 0.45, 0.25, 0.62, 0.36, 0.72}
  # Play opens this long after the first shell, a peony, bursts.
  @open 0.55
  # Cells a stroke is sampled in.
  @n 24

  @compile {:inline, cell: 2, pos: 3, streak: 2, flicker: 2}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    s = shell(0)
    %{lead: s.at + s.rise + @open, cache: %{0 => s}}
  end

  # One shell, everything about it drawn from its own seed.
  defp shell(i) do
    r = Int32.to_int32(i * 7919 + 17)
    {r1, r} = Int32.mulberry32(r)
    {r2, r} = Int32.mulberry32(r)
    {r3, r} = Int32.mulberry32(r)
    {r4, r} = Int32.mulberry32(r)
    {r5, r} = Int32.mulberry32(r)
    kind = elem(@kinds, Integer.mod(i, tuple_size(@kinds)))
    spot = elem(@spots, Integer.mod(i, tuple_size(@spots)))

    s = %{
      kind: kind,
      at: i * @every + r1 * 0.25,
      x0: @cols * (spot + (r2 - 0.5) * 0.05),
      drift: (r3 - 0.5) * 2,
      rise: 1 + r4 * 0.2,
      top: @sky * (0.62 + r5 * 0.08)
    }

    {sparks, _} = sparks(kind, r)
    Map.merge(s, %{sparks: sparks, bx: s.x0 + s.drift * s.rise})
  end

  defp sparks(:peony, r), do: sphere(r, 27, 33, %{look: :peony}, true)

  defp sparks(:willow, r),
    do: sphere(r, 15, 30, %{look: :willow, k: 2.1, life: 3.4}, false)

  defp sparks(:ring, r), do: ring(r, 24, 28, %{look: :ring, life: 1.5}, 0.3)

  defp sparks(:saturn, r) do
    {a, r} = ring(r, 24, 30, %{look: :ring, life: 1.5}, 0.5)
    {b, r} = sphere(r, 9, 10, %{look: :core, life: 1.1}, true)
    {a ++ b, r}
  end

  defp sparks(:palm, r) do
    # A palm: a few heavy comets fanned up and out, drooping as they slow.
    Enum.map_reduce(0..6, r, fn j, r ->
      {x, r} = Int32.mulberry32(r)
      a = :math.pi() / 2 + (j - 3) / 3 * 1.15 + (x - 0.5) * 0.08
      add(r, :math.cos(a) * 36, :math.sin(a) * 36, %{look: :palm, k: 2.2, life: 1.9})
    end)
  end

  defp add(r, vx, vy, o) do
    {x, r} = Int32.mulberry32(r)
    p = Map.merge(%{vx: vx, vy: vy, k: 2.2, life: 1.7, seed: trunc(x * 1.0e9), inner: false}, o)
    {Map.put(p, :gk, @g / p.k), r}
  end

  # A sphere seen from outside: headings evenly round the sky, and most sparks
  # out at the rim, where a sphere's sparks crowd when it is seen flat. With
  # `deep`, every third one is thrown nearer the eye and shows further in.
  defp sphere(r, count, speed, o, deep) do
    {x, r} = Int32.mulberry32(r)
    turn = x * 6.283

    Enum.map_reduce(0..(count - 1), r, fn j, r ->
      a = turn + (j + 0.5) / count * 6.283
      inner = deep and rem(j, 3) == 1

      {reach, r} =
        if inner do
          {0.5 + 0.25 * (rem(j * 7, 5) / 4), r}
        else
          {y, r} = Int32.mulberry32(r)
          {0.94 + y * 0.06, r}
        end

      add(
        r,
        :math.cos(a) * speed * reach,
        :math.sin(a) * speed * reach,
        Map.put(o, :inner, inner)
      )
    end)
  end

  # A flat ring tipped toward the viewer, so it shows as an ellipse.
  defp ring(r, count, speed, o, open) do
    {x, r} = Int32.mulberry32(r)
    {y, r} = Int32.mulberry32(r)
    tilt = open + x * 0.15
    roll = (y - 0.5) * 0.5
    cr = :math.cos(roll)
    sr = :math.sin(roll)

    Enum.map_reduce(0..(count - 1), r, fn j, r ->
      a = j / count * 6.283
      x = :math.cos(a)
      y = :math.sin(a) * tilt
      add(r, (x * cr - y * sr) * speed, (x * sr + y * cr) * speed, o)
    end)
  end

  # The heading of a streak picks its glyph, with rows counted double.
  defp streak(dx, dy) do
    a = :math.atan2(dy, dx)
    a = if a < 0, do: a + :math.pi(), else: a

    cond do
      a < 0.42 or a > 2.72 -> "-"
      a < 1.2 -> "/"
      a < 1.94 -> "|"
      true -> "\\"
    end
  end

  defp cell(x, y) do
    c = floor(x)
    r = floor(@rows - y / 2)
    if c >= 0 and c < @cols and r >= 0 and r < @rows, do: c + r * @cols, else: -1
  end

  defp put(grid, x, y, ch) do
    case cell(x, y) do
      -1 -> grid
      k -> Map.put(grid, k, ch)
    end
  end

  # Where a spark is b seconds after the burst. Drag spends its throw
  # exponentially, so its reach so far is (1 - e^-kb) / k of its speed.
  defp pos(s, p, b) do
    e = (1 - :math.exp(-p.k * b)) / p.k
    {s.bx + p.vx * e, s.top + p.vy * e - p.gk * (b - e)}
  end

  # The age at which a spark has gone a share q of the way out it has gone by age a.
  defp back(p, a, q), do: -:math.log(1 - q * (1 - :math.exp(-p.k * a))) / p.k

  # Lays a spark's path from age b0 to b1 into cells, one glyph a cell, back
  # from the head; the style picks it from how far back it is (0 to 1) and
  # which cell of the stroke it is.
  defp stroke(grid, _s, _p, b0, b1, _style) when b1 <= b0, do: grid

  defp stroke(grid, s, p, b0, b1, style) do
    {x, y} = pos(s, p, b1)

    {grid, _, _} =
      Enum.reduce(1..@n, {grid, cell(x, y), 0}, fn j, {grid, last, m} = acc ->
        b = b1 - (b1 - b0) * j / @n
        {x, y} = pos(s, p, b)
        k = cell(x, y)

        if k < 0 or k == last do
          acc
        else
          {nx, ny} = pos(s, p, b + 0.01)

          case glyph(style, j / @n, nx - x, ny - y, m) do
            "" -> {grid, k, m + 1}
            g -> {Map.put(grid, k, g), k, m + 1}
          end
        end
      end)

    grid
  end

  defp glyph(:peony, _u, dx, dy, _m), do: streak(dx, dy)
  defp glyph(:willow, u, dx, dy, _m) when u < 0.6, do: streak(dx, dy)
  defp glyph(:willow, _u, _dx, _dy, m), do: if(rem(m, 2) == 1, do: "", else: ".")
  defp glyph(:palm, u, dx, dy, _m) when u < 0.9, do: streak(dx, dy)
  defp glyph(:palm, _u, _dx, _dy, _m), do: "."

  # A spark's flicker hash for this tick, in [0, 1).
  defp flicker(seed, tick) do
    h = Int32.umul(bxor(Int32.u32(seed), Int32.umul(Int32.u32(tick), 0x9E3779B1)), 0x85EBCA6B)
    rem(bxor(h, bsr(h, 13)), 1000) / 1000
  end

  @impl true
  def frame(%{lead: lead, cache: cache} = state, time, _env) do
    t = time + lead
    tick = floor(t * 30)
    last = floor(t / @every)

    {grid, cache} =
      Enum.reduce((last - 4)..last, {%{}, cache}, fn i, {grid, cache} ->
        cache = Map.put_new_lazy(cache, i, fn -> shell(i) end)
        s = Map.fetch!(cache, i)

        {draw(grid, s, t - s.at, i, tick), cache}
      end)

    cache = Map.reject(cache, fn {i, _} -> i < last - 5 end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(grid, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, %{state | cache: cache}}
  end

  defp draw(grid, _s, age, _i, _tick) when age < 0, do: grid

  defp draw(grid, %{rise: rise} = s, age, i, tick) when age < rise do
    # Climbing: slowing toward the top, with sparks dropping off behind.
    g = 2 * s.top / (rise * rise)
    v0 = g * rise

    grid =
      Enum.reduce(5..1//-1, grid, fn j, grid ->
        a = age - j * 0.05

        if a < 0 or rem(tick + j + i, 3) == 0 do
          grid
        else
          {x, y} = climb(s, g, v0, a)

          put(
            grid,
            x + (rem(tick * 7 + j, 3) - 1) * 0.4,
            y - j * 0.3,
            if(j > 3, do: ".", else: ":")
          )
        end
      end)

    {x, y} = climb(s, g, v0, age)
    put(grid, x, y, "|")
  end

  defp draw(grid, s, age, _i, tick) do
    a = age - s.rise

    {grid, heads} =
      Enum.reduce(s.sparks, {grid, []}, fn p, {grid, heads} = acc ->
        f = a / p.life

        cond do
          a > p.life -> acc
          # Near the end a spark flickers before it goes out.
          f > 0.7 and flicker(p.seed, tick) < (f - 0.7) * 3 -> acc
          # Packed together just after the burst, the sparks would only blot.
          a < 0.1 -> acc
          true -> spark(grid, heads, s, p, a, f)
        end
      end)

    grid =
      heads |> Enum.reverse() |> Enum.reduce(grid, fn {x, y, g}, grid -> put(grid, x, y, g) end)

    # The flash at the moment of the burst.
    if a < 0.12,
      do: put(grid, s.bx, s.top, if(a < 0.06, do: "@", else: "*")),
      else: grid
  end

  defp climb(s, g, v0, a), do: {s.x0 + s.drift * a, v0 * a - g * a * a / 2}

  defp spark(grid, heads, s, %{look: :peony} = p, a, f) do
    {x, y} = pos(s, p, a)

    # A short streak behind each rim spark, on the outer part of its path
    # only, so the middle stays open and the burst is round.
    grid =
      if not p.inner and a < 0.75,
        do: stroke(grid, s, p, max(back(p, a, 0.6), a - 0.12), a, :peony),
        else: grid

    g =
      cond do
        a < 0.7 -> "*"
        f < 0.6 -> "+"
        true -> "."
      end

    {grid, [{x, y, g} | heads]}
  end

  defp spark(grid, heads, _s, %{look: :ring}, a, _f) when a < 0.15, do: {grid, heads}

  defp spark(grid, heads, s, %{look: :ring} = p, a, f) do
    {x, y} = pos(s, p, a)
    {grid, [{x, y, if(a < 0.3 or f > 0.6, do: ".", else: "o")} | heads]}
  end

  defp spark(grid, heads, s, %{look: :core} = p, a, f) do
    {x, y} = pos(s, p, a)
    {grid, [{x, y, if(f < 0.5, do: "+", else: ".")} | heads]}
  end

  defp spark(grid, heads, s, %{look: :willow} = p, a, f) do
    {x, y} = pos(s, p, a)
    # Gold threads that hang, thinning from a line to dots.
    grid = stroke(grid, s, p, max(back(p, a, 0.45), a - 1.6), a, :willow)
    {grid, [{x, y, if(f < 0.25, do: "*", else: ".")} | heads]}
  end

  defp spark(grid, heads, s, %{look: :palm} = p, a, f) do
    {x, y} = pos(s, p, a)
    # A palm comet: one heavy head and a curved tail that tapers off.
    grid = stroke(grid, s, p, max(back(p, a, 0.45), a - 1), a, :palm)

    g =
      cond do
        a < 0.2 -> "*"
        a < 0.45 -> "@"
        f < 0.75 -> "o"
        true -> "."
      end

    {grid, [{x, y, g} | heads]}
  end
end
