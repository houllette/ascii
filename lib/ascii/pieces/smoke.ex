defmodule Ascii.Pieces.Smoke do
  @moduledoc """
  Incense smoke rising straight, then curling and thinning.

  A thread of smoke from a stick of incense. It leaves the ember as a
  straight line, starts to waver, frays into curls and thins to nothing.

  Ported from `src/pieces/smoke.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.Int32

  @meta %Ascii.Meta{
    name: "smoke",
    category: :physics,
    note: "incense smoke rising straight, then curling and thinning",
    cols: 44,
    rows: 24,
    fps: 30
  }

  # Smoke is ink on either ground, so the ramp is not flipped on paper. Thin
  # to thick.
  @ramp {" ", ".", "·", ":", ";", "+"}
  # The ember's row; puffs a second leaving the ember; seconds a puff lasts;
  # rows a second, near the ember.
  @tip 17
  @rate 70
  @life 8
  @rise 3.4
  # Ages over which the thread gives way to haze.
  @fray0 2.3
  @fray1 3.6
  # Loose eddies higher up, as waves of a stream function: wavelength in rows,
  # heading, drift, strength.
  @waves [{8, 0.4, 0.5, 1}, {5.5, 2.3, -0.8, 0.9}, {3.6, 1.1, 1.1, 0.6}, {11, -1, 0.3, 0.8}]

  @cols 44
  @rows 24
  @cx div(@cols, 2) + 0.5

  @compile {:inline, smooth: 3}

  @impl true
  def meta, do: @meta

  defp smooth(a, b, x) do
    u = min(1, max(0, (x - a) / (b - a)))
    u * u * (3 - 2 * u)
  end

  @impl true
  def init(_options) do
    {waves, rand} =
      Enum.map_reduce(@waves, Int32.to_int32(11), fn {len, ang, drift, amp}, rand ->
        k = 2 * :math.pi() / len
        {ph, rand} = Int32.mulberry32(rand)
        {{k * :math.cos(ang), k * :math.sin(ang), drift, amp * 1.6, ph * 6.283}, rand}
      end)

    # Nine seconds, so the column is full.
    sim = %{puffs: :queue.new(), clock: 0, made: 0, rand: rand, waves: waves}
    sim = Enum.reduce(1..270, sim, fn _, sim -> step(sim, 1 / 30) end)
    Map.put(sim, :last, 0)
  end

  # Puffs in the order they left the ember, so neighbours trace one thread.
  # Each carries a little noise that decides where the thread breaks.
  defp step(sim, dt) do
    clock = sim.clock + dt
    {puffs, made, rand} = emit(sim.puffs, sim.made, sim.rand, clock)
    air = air(clock, sim.waves)

    puffs =
      :queue.filter(
        fn {x, y, age, n, cut} ->
          {u, v} = flow(x, y, air)
          [{x + u * dt, y + v * dt, age + dt, n, cut}]
        end,
        puffs
      )

    %{sim | puffs: drop_old(puffs), clock: clock, made: made, rand: rand}
  end

  defp emit(puffs, made, rand, clock) when made < clock * @rate do
    age = clock - made / @rate
    {r, rand} = Int32.mulberry32(rand)
    cut = r * 0.7 + 0.3 * :math.sin(made * 0.09)
    emit(:queue.in({0, age * @rise, age, made, cut}, puffs), made + 1, rand, clock)
  end

  defp emit(puffs, made, rand, _clock), do: {puffs, made, rand}

  defp drop_old(puffs) do
    case :queue.peek(puffs) do
      {:value, {_, y, age, _, _}} when age > @life or y > @tip + 3 ->
        drop_old(:queue.drop(puffs))

      _ ->
        puffs
    end
  end

  # What the air does at time t, the same for every puff.
  defp air(t, waves) do
    %{
      rise08: @rise * 0.8 * t,
      sway: 0.4 * :math.sin(t * 0.37),
      rise07: @rise * 0.7 * t,
      drift: 0.15 * :math.sin(t * 0.55),
      waves: for({kx, ky, w, a, ph} <- waves, do: {kx, ky, w * t, a, ph})
    }
  end

  # The air at (x, y), in rows from the ember. It rises and slows as it cools.
  # A row of eddies riding up the plume makes the thread waver and roll, and
  # looser eddies above break it up. Where a term is weighted by zero it is
  # left out: it could only add a zero.
  defp flow(x, y, air) do
    k = 1.05
    lift = 1.7 * smooth(1.5, 7, y) * (1 - 0.5 * smooth(9, 15, y))

    {u, v} =
      if lift == 0 do
        {0, 0}
      else
        s = k * (y - air.rise08) + air.sway
        q = x / 2.2
        g = :math.exp(-(q * q))
        {lift * g * :math.cos(s), lift * g * :math.sin(s) * 2 * x / (2.2 * 2.2 * k)}
      end

    e = smooth(6, 12, y)

    {u, v} =
      if e == 0 do
        {u, v}
      else
        yy = y - air.rise07

        Enum.reduce(air.waves, {u, v}, fn {kx, ky, wt, a, ph}, {u, v} ->
          c = :math.cos(kx * x + ky * yy + wt + ph) * a * e
          {u + c * ky / 1.2, v - c * kx / 1.2}
        end)
      end

    {u + air.drift * smooth(0.5, 5, y), @rise * (1 - 0.35 * smooth(3, 15, y)) + 0.5 * v}
  end

  @impl true
  def frame(sim, time, _env) do
    dt = min(0.1, max(0, time - sim.last))
    sim = run(%{sim | last: time}, dt)
    puffs = :queue.to_list(sim.puffs)
    n = length(puffs)
    xs = List.to_tuple(for {x, _, _, _, _} <- puffs, do: @cx + 2 * x)
    ys = List.to_tuple(for {_, y, _, _, _} <- puffs, do: @tip + 0.5 - y)

    haze = haze(puffs, xs, ys)
    {g, line} = thread(puffs, xs, ys, n)

    # Haze fills in round the thread, its faintest edge dropped.
    g =
      Enum.reduce(haze, g, fn {k, h}, g ->
        h = h * 0.5

        if Map.has_key?(line, k) or h < 0.07,
          do: g,
          else:
            Map.put(g, k, elem(@ramp, min(tuple_size(@ramp) - 1, 1 + floor(:math.sqrt(h) * 2.3))))
      end)

    {Enum.intersperse(stick(g, time), ?\n), nil, sim}
  end

  defp run(sim, dt) when dt > 1.0e-9, do: run(step(sim, min(dt, 1 / 30)), dt - 1 / 30)
  defp run(sim, _dt), do: sim

  # An old puff has let go of the thread and spreads as haze, thinning as it goes.
  defp haze(puffs, xs, ys) do
    {haze, _} =
      Enum.reduce(puffs, {%{}, 0}, fn {_, _, age, _, _}, {haze, i} ->
        loose = smooth(@fray0 - 0.4, @fray1, age)
        {if(loose <= 0, do: haze, else: spread(haze, age, loose, xs, ys, i)), i + 1}
      end)

    haze
  end

  defp spread(haze, age, loose, xs, ys, i) do
    rad = 0.55 + 0.2 * (age - @fray0 + 0.4)
    rad2 = rad * rad
    m = loose * :math.exp(-(age - @fray0) / 1.7) / rad2
    col = elem(xs, i)
    row = elem(ys, i)

    for rr <- max(0, floor(row - rad))..floor(min(@rows - 1, row + rad))//1,
        cc <- max(0, floor(col - 2 * rad))..floor(min(@cols - 1, col + 2 * rad))//1,
        dx = (cc + 0.5 - col) / 2,
        dy = rr + 0.5 - row,
        d2 = (dx * dx + dy * dy) / rad2,
        d2 < 1,
        reduce: haze do
      haze ->
        k = rr * @cols + cc
        Map.put(haze, k, Map.get(haze, k, 0) + m * (1 - d2) * (1 - d2))
    end
  end

  # The thread: where it crosses each row's middle, one stroke, slanted by how
  # fast it runs sideways there and bowed where it bends.
  defp thread(puffs, xs, ys, n) do
    hits =
      puffs
      |> Enum.take(max(n - 1, 0))
      |> Enum.with_index()
      |> Enum.flat_map(fn {{_, _, age, _, cut}, i} ->
        hold = 1 - smooth(@fray0, @fray1, age)
        # Broken here.
        if hold < cut * 0.9, do: [], else: crossing(i, hold, xs, ys, n)
      end)
      |> List.to_tuple()

    Enum.reduce(0..(tuple_size(hits) - 1)//1, {%{}, %{}}, fn h, {g, line} ->
      {r, x, s, hold} = elem(hits, h)
      c = floor(x)
      k = r * @cols + c

      if c < 0 or c >= @cols or Map.get(line, k, 0) >= hold do
        {g, line}
      else
        {Map.put(g, k, stroke(hits, h, r, x, s)), Map.put(line, k, hold)}
      end
    end)
  end

  defp crossing(i, hold, xs, ys, n) do
    y0 = elem(ys, i)
    y1 = elem(ys, i + 1)
    r = floor(max(y0, y1) - 0.5)

    if r < 0 or min(y0, y1) > r + 0.5 or y0 == y1 do
      []
    else
      u = (r + 0.5 - y0) / (y1 - y0)
      x = elem(xs, i) + u * (elem(xs, i + 1) - elem(xs, i))
      a = max(0, i - 3)
      b = min(n - 1, i + 4)

      dy = elem(ys, b) - elem(ys, a)
      dy = if dy == 0, do: 1.0e-6, else: dy

      [{r, x, (elem(xs, b) - elem(xs, a)) / dy, hold}]
    end
  end

  defp stroke(hits, h, r, x, s) do
    bend =
      with true <- h > 0 and h + 1 < tuple_size(hits),
           {ur, ux, _, _} when ur == r - 1 <- elem(hits, h - 1),
           {dr, dx, _, _} when dr == r + 1 <- elem(hits, h + 1) do
        x - (ux + dx) / 2
      else
        _ -> 0
      end

    cond do
      abs(s) < 1.1 and abs(bend) > 0.45 -> if bend < 0, do: "(", else: ")"
      abs(s) < 0.6 -> "|"
      abs(s) < 3.2 -> if s < 0, do: "/", else: "\\"
      true -> "-"
    end
  end

  # The stick and its smouldering ember, standing in a bowl of ash.
  defp stick(g, time) do
    sc = floor(@cx)

    glow =
      0.55 + 0.25 * :math.sin(time * 1.9) + 0.15 * :math.sin(time * 4.7 + 1) +
        0.12 * :math.sin(time * 11.3 + 2)

    ember =
      cond do
        glow > 0.5 -> "*"
        glow > 0.2 -> "+"
        true -> "·"
      end

    g = Map.put(g, @tip * @cols + sc, ember)
    g = Enum.reduce((@tip + 1)..(@rows - 3), g, &Map.put(&2, &1 * @cols + sc, "┃"))

    g =
      ["._______┃_______.", "\\_______________/"]
      |> Enum.with_index(@rows - 2)
      |> Enum.reduce(g, fn {s, r}, g ->
        s
        |> String.codepoints()
        |> Enum.with_index(sc - 8)
        |> Enum.reduce(g, fn {ch, c}, g -> Map.put(g, r * @cols + c, ch) end)
      end)

    for r <- 0..(@rows - 1) do
      for c <- 0..(@cols - 1), do: Map.get(g, r * @cols + c, " ")
    end
  end
end
