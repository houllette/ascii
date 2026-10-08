defmodule AsciiArt.Pieces.Campfire do
  @moduledoc """
  A log fire flickering, sparks rising; denser ink is hotter.

  Two logs lying crossed on the ground, burning where they meet. Tongues of
  flame sway and tear over a low body of fire, the bark chars and glows
  beneath them, and sparks lift off the tips as they climb.

  Ported from `src/pieces/campfire.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Hash

  @meta %AsciiArt.Meta{
    name: "campfire",
    category: :nature,
    note: "a log fire flickering, sparks rising; denser ink is hotter",
    cols: 52,
    rows: 22,
    fps: 20
  }

  @cols 52
  @rows 22
  @cx 52 / 2
  # Coolest to hottest. Fire is light, so it keeps its ramp on paper, where
  # the hottest parts print as the densest ink.
  @fire {" ", ".", ",", ":", ";", "=", "+", "*", "#", "%", "@"}
  @ember {":", ";", "+", "*", "#", "%"}
  # A log's edge by where it crosses its cell, bottom to top.
  @surf {"_", ".", "-", "'"}
  # The row the flames stand on.
  @bed 18.4
  # The rows the fire is worked out for: up to ceil(@bed).
  @top_rows 19
  # Tongues: {columns off centre, height in rows, half width, phase}.
  @tongues [
    {-7.4, 9.5, 3.4, 2.4},
    {-4.4, 12.5, 3.5, 0.0},
    {-1.4, 15, 3.5, 1.7},
    {1.7, 15.5, 3.5, 3.1},
    {4.7, 12.5, 3.5, 4.4},
    {7.6, 10, 3.4, 5.6}
  ]
  # The logs cross in the fire, each lying low across the frame: {the side
  # its near end lies on, half its length in columns, rows it drops a column
  # toward that end, radius in rows}. @mid is the row their axes cross at.
  @mid 16.8
  @logs [{1, 22, 0.115, 1.4}, {-1, 22, 0.115, 1.4}]
  @sparks 9

  @impl true
  def meta, do: @meta

  @compile {:inline, ease: 1}
  defp ease(t), do: t * t * (3 - 2 * t)

  defp noise(x, y) do
    i = floor(x)
    j = floor(y)
    u = ease(x - i)
    v = ease(y - j)
    a = Hash.murmur(i, j)
    b = Hash.murmur(i + 1, j)
    c = Hash.murmur(i, j + 1)
    d = Hash.murmur(i + 1, j + 1)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  @impl true
  def init(_options) do
    logs = logs()

    # Sparks: each rises from the flames on its own period, wavering.
    sparks =
      for i <- 0..(@sparks - 1) do
        {(Hash.murmur(i, 1) - 0.5) * 12, 2.6 + Hash.murmur(i, 2) * 2.4,
         (i + Hash.murmur(i, 3) * 0.5) / @sparks, 7 + Hash.murmur(i, 4) * 6,
         (Hash.murmur(i, 5) - 0.5) * 8}
      end

    # Coals on the ground under the crossing, brightest in the middle.
    coals =
      for r <- (ceil(@bed) - 1)..(@rows - 1),
          c <- 0..(@cols - 1),
          x = c + 0.5 - @cx,
          not Map.has_key?(logs, c + r * @cols) and abs(x) <= 10 do
        q = x / 6

        {c + r * @cols, :math.exp(-(q * q)) * (1.3 - (r + 1 - @bed) * 0.35),
         Hash.murmur(c, r + 60) * 9}
      end

    # Each column's place in the two noises that tear the fire: the lattice
    # cell and the eased offset into it, which do not change.
    columns =
      for c <- 0..(@cols - 1) do
        x = c + 0.5 - @cx
        a1 = x * 0.45
        a2 = x * 0.9 + 9
        i1 = floor(a1)
        i2 = floor(a2)
        {x, i1, ease(a1 - i1), i2, ease(a2 - i2)}
      end

    lo1 = columns |> Enum.map(&elem(&1, 1)) |> Enum.min()
    hi1 = columns |> Enum.map(&elem(&1, 1)) |> Enum.max()
    lo2 = columns |> Enum.map(&elem(&1, 3)) |> Enum.min()
    hi2 = columns |> Enum.map(&elem(&1, 3)) |> Enum.max()

    log_rows =
      for r <- 0..(@rows - 1) do
        List.to_tuple(for c <- 0..(@cols - 1), do: Map.get(logs, c + r * @cols))
      end

    %{
      logs: List.to_tuple(log_rows),
      sparks: sparks,
      coals: coals,
      columns: columns,
      spans: {lo1, hi1, lo2, hi2}
    }
  end

  # Each log as cells: a glyph, how hot the fire makes it (the top of the log
  # most, and the more the nearer the middle), and whether it is the near
  # half. The near half of a log, toward us, is drawn over the far half of
  # the other.
  defp logs do
    for {side, half, k, rr} <- @logs,
        c <- floor(@cx - half)..ceil(@cx + half - 1),
        c < @cx + half,
        reduce: %{} do
      logs -> log_column(logs, side, half, k, rr, c)
    end
  end

  defp log_column(logs, side, half, k, rr, c) do
    seed = if side > 0, do: 3, else: 8
    x = c + 0.5 - @cx
    y = @mid + k * x * side
    # The near end is cut and shows its rings.
    front = if x * side > 0, do: 1, else: 0
    r0 = floor(y - rr)
    r1 = floor(y + rr)
    q = x / 13
    warm = :math.exp(-(q * q))
    # How far in from the end of the log, in columns.
    e = min(c - floor(@cx - half), ceil(@cx + half) - 1 - c)

    top = if e == 0 or (front == 1 and e == 1), do: " ", else: surf(1 - (y - rr - r0))
    bottom = if e == 0 or (front == 1 and e < 3), do: " ", else: surf(1 - (y + rr - r1))
    logs = logs |> set(c, r0, front, top, warm) |> set(c, r1, front, bottom, 0)

    # Bark in runs along the log that break and change: ridged where the
    # firelight catches it on top, plainer in its own shadow below.
    Enum.reduce((r0 + 1)..(r1 - 1)//1, logs, fn r, logs ->
      upper = r == r0 + 1
      u = x * side + if(upper, do: 0, else: 1.7) + 40
      run = floor(u / 2.6)
      h = Hash.murmur(run, seed + if(upper, do: 0, else: 5))
      ch = bark_end(e, front == 1, upper, x < 0) || bark(rem(run, 2) == 1, upper, h)
      set(logs, c, r, front, ch, warm * if(upper, do: 0.7, else: 0.3))
    end)
  end

  defp surf(v), do: elem(@surf, min(3, floor(v * 4)))

  # The ends of a log: the far end round, the near end cut to show its rings.
  defp bark_end(0, true, upper, left), do: if(upper == left, do: "/", else: "\\")
  defp bark_end(0, false, _upper, left), do: if(left, do: "(", else: ")")
  defp bark_end(1, true, upper, _left), do: if(upper, do: "@", else: "_")
  defp bark_end(2, true, upper, left), do: if(upper == left, do: "\\", else: "/")
  defp bark_end(_e, _front, _upper, _left), do: nil

  defp bark(true, true, _h), do: "="
  defp bark(true, false, _h), do: "-"
  defp bark(false, true, h), do: if(h < 0.6, do: "#", else: ":")
  defp bark(false, false, h), do: if(h < 0.6, do: "=", else: ".")

  defp set(logs, _c, r, _front, _ch, _h) when r < 0 or r >= @rows, do: logs

  defp set(logs, c, r, front, ch, h) do
    i = c + r * @cols

    case logs do
      %{^i => {_, _, 1}} when front == 0 -> logs
      _ -> Map.put(logs, i, {ch, JSMath.fround(h), front})
    end
  end

  @impl true
  def frame(state, t, _env) do
    breath = 0.85 + 0.3 * noise(t * 3, 7.5)

    tongues =
      for {x0, h0, w0, ph} <- @tongues do
        {x0, w0, ph, h0 * (0.72 + 0.5 * noise(t * 1.6 + ph * 3, ph * 5)) * breath,
         :math.sin(t * 8.3 + ph * 2)}
      end

    fr = %{t: t, breath: breath, tongues: tongues, t55: t * 5.5, t6: t * 6, t8: t * 8}

    fire =
      for r <- 0..(@top_rows - 1) do
        subs = [sub(r + 0.25, fr, state.spans), sub(r + 0.75, fr, state.spans)]

        List.to_tuple(
          for col <- state.columns do
            v = Enum.reduce(subs, 0, fn sp, v -> v + flame(sp, col) end)
            JSMath.fround(v / 2)
          end
        )
      end

    reached = List.to_tuple(reach(fire))
    fire = List.to_tuple(fire)

    base =
      for r <- 0..(@rows - 1) do
        log_row = elem(state.logs, r)
        {fire_row, reach_row} = fire_at(fire, reached, r)

        for c <- 0..(@cols - 1) do
          cell(elem(log_row, c), elem(fire_row, c), elem(reach_row, c), c, r, t)
        end
      end
      |> List.flatten()
      |> List.to_tuple()

    # Coals glow on the ground under the crossing.
    over =
      Enum.reduce(state.coals, %{}, fn {k, w, ph}, over ->
        b = w * (0.35 + 0.8 * noise(ph + t * 1.3, ph * 3)) - 0.2

        if b > 0 and elem(base, k) == " ",
          do: Map.put(over, k, elem(@ember, min(5, floor(b * 6)))),
          else: over
      end)

    over = Enum.reduce(state.sparks, over, &spark(&1, &2, t, base))

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), k = c + r * @cols, do: Map.get(over, k, elem(base, k))
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  @no_fire List.to_tuple(List.duplicate(0, @cols))
  @no_reach List.to_tuple(List.duplicate(false, @cols))

  defp fire_at(fire, reached, r) when r < @top_rows, do: {elem(fire, r), elem(reached, r)}

  defp fire_at(_fire, _reached, _r), do: {@no_fire, @no_reach}

  # Everything about a half row that does not change across it: the low body
  # of fire, the tongues that reach it, and the rows of both noises.
  defp sub(at, fr, {lo1, hi1, lo2, hi2}) do
    h = @bed - at
    # A low body of fire across the crossing, and the tongues rising out of
    # it, the outer ones leaning in toward the middle.
    low = h / (5.5 * fr.breath)
    body = if low < 1, do: {10.5 * :math.sqrt(1 - low) + 0.5, 0.85 - low * 0.5, low * 0.5}

    tongues =
      for {x0, w0, ph, span, wave} <- fr.tongues,
          lift = h / span,
          # Below the bed a tongue's sway is NaN in JS, and so never wins.
          lift < 1 and lift >= 0 do
        sway =
          1.4 * :math.pow(lift, 1.4) * :math.sin(h * 0.55 - fr.t55 + ph) + 0.5 * lift * wave

        {x0 * (1 - 0.45 * lift), sway, w0 * :math.pow(1 - lift, 0.6) + 0.5, 1 - lift * 0.6, lift}
      end

    # Rising noise tears the fire, more toward the tips than the base.
    y1 = (h - fr.t6) * 0.35
    y2 = (h - fr.t8) * 0.7
    j1 = floor(y1)
    j2 = floor(y2)

    {body, tongues, lattice(lo1, hi1, j1), ease(y1 - j1), lo1, lattice(lo2, hi2, j2),
     ease(y2 - j2), lo2}
  end

  defp lattice(lo, hi, j) do
    List.to_tuple(for i <- lo..(hi + 1), do: {Hash.murmur(i, j), Hash.murmur(i, j + 1)})
  end

  @compile {:inline, lattice_noise: 5}
  defp lattice_noise(lat, i, u, v, lo) do
    {a, c} = elem(lat, i - lo)
    {b, d} = elem(lat, i + 1 - lo)
    a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
  end

  defp flame({body, tongues, lat1, v1, lo1, lat2, v2, lo2}, {x, i1, u1, i2, u2}) do
    {m, top} =
      case body do
        nil ->
          {0, 0}

        {width, depth, top} ->
          q = x / width
          {(1 - q * q) * depth, top}
      end

    {m, top} =
      Enum.reduce(tongues, {m, top}, fn {x0, sway, width, fall, lift}, {m, top} ->
        q = (x - x0 - sway) / width
        f = (1 - q * q) * fall
        if f > m, do: {f, lift}, else: {m, top}
      end)

    n = lattice_noise(lat1, i1, u1, v1, lo1) * 0.6 + lattice_noise(lat2, i2, u2, v2, lo2) * 0.4
    m - 0.55 * n * (0.35 + top * 0.65)
  end

  # Only flame that joins the body of the fire is drawn: a tongue that tears
  # free goes out. Flame spreads from the bottom row up and sideways, so a
  # row's lit cells are the runs of flame that touch one lit just below.
  defp reach(fire) do
    [bottom | above] = Enum.reverse(fire)
    first = bottom |> Tuple.to_list() |> Enum.map(&(&1 > 0.03)) |> List.to_tuple()

    above
    |> Enum.reduce([first], fn row, [below | _] = acc ->
      [reach_row(row, below) | acc]
    end)
  end

  defp reach_row(row, below) do
    hot = for c <- 0..(@cols - 1), do: elem(row, c) > 0.03

    entry =
      for {h, c} <- Enum.with_index(hot) do
        h and
          ((c > 0 and elem(below, c - 1)) or elem(below, c) or
             (c < @cols - 1 and elem(below, c + 1)))
      end

    hot
    |> Enum.zip(entry)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(fn [{h, _} | _] = run ->
      lit = h and Enum.any?(run, &elem(&1, 1))
      List.duplicate(lit, length(run))
    end)
    |> List.to_tuple()
  end

  # The near halves of the logs stand in front of all but the hottest flame;
  # the far halves go behind it.
  defp cell(log, f, true, c, r, t) do
    v = JSMath.fround(f + 2) - 2

    if v > 0.03 and not (log != nil and elem(log, 2) == 1 and v < 0.6),
      do: elem(@fire, min(10, 1 + floor((v - 0.03) / 0.85 * 10))),
      else: cell(log, f, false, c, r, t)
  end

  defp cell(nil, _f, false, _c, _r, _t), do: " "

  defp cell({ch, heat, _near}, _f, false, c, r, t) do
    g = heat * (0.45 + 0.75 * noise(c * 0.7 + 3, t * 2.2 + r * 3)) - 0.3
    if g > 0, do: elem(@ember, min(5, floor(g * 1.6 * 6))), else: ch
  end

  defp spark({_sx, period, phase, _rise, _drift} = spark, over, t, base) do
    u = JSMath.mod(t / period + phase, 1)
    if u > 0.8, do: over, else: spark_at(spark, u, over, base)
  end

  defp spark_at({sx, _period, phase, rise, drift}, u, over, base) do
    y = @bed - 8 - u * rise
    x = @cx + sx + drift * u + :math.sin(u * 11 + phase * 6)
    c = floor(x)
    r = floor(y)
    k = c + r * @cols

    cond do
      r < 0 or c < 0 or c >= @cols -> over
      Map.get(over, k, elem(base, k)) != " " -> over
      u < 0.25 -> Map.put(over, k, "*")
      u < 0.45 -> Map.put(over, k, "+")
      u < 0.65 -> Map.put(over, k, "'")
      true -> Map.put(over, k, ".")
    end
  end
end
