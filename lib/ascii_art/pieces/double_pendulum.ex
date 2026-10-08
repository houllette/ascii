defmodule AsciiArt.Pieces.DoublePendulum do
  @moduledoc """
  A chaotic double pendulum; its tip leaves a fading trail.

  Two equal rods hung end to end from one pivot, stepped with RK4. Chaotic,
  so it never repeats; the lower bob leaves a fading trail.

  Ported from `src/pieces/double-pendulum.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "double pendulum",
    category: :physics,
    note: "a chaotic double pendulum; its tip leaves a fading trail",
    cols: 48,
    rows: 25,
    fps: 30
  }

  @g 9.81
  # Integrator step, in seconds of model time; model seconds per second of play.
  @h 1 / 240
  @speed 0.6
  # Steps between trail samples, and trail samples kept.
  @tap 3
  @trail 110
  # Trail glyphs, oldest first.
  @fade {"·", ":", "+", "*"}
  # Both angles from straight down, then their rates.
  @start {2.55, 2.9, 0, 0}
  # Model seconds run before the first frame.
  @warm 7

  @cols 48
  @rows 25
  @cx (@cols - 1) / 2
  @cy (@rows - 1) / 2
  # Both rods reach any edge but none clips.
  @sy (@cy - 0.6) / 2
  @sx @sy * 2

  @impl true
  def meta, do: @meta

  # Unit masses and rods. s = {angle 1, angle 2, rate 1, rate 2}.
  defp deriv({a, b, p, q}) do
    d = a - b
    sd = :math.sin(d)
    cd = :math.cos(d)
    den = 3 - :math.cos(2 * d)

    {p, q,
     (-3 * @g * :math.sin(a) - @g * :math.sin(a - 2 * b) - 2 * sd * (q * q + p * p * cd)) / den,
     2 * sd * (2 * p * p + 2 * @g * :math.cos(a) + q * q * cd) / den}
  end

  defp add({a, b, p, q}, {ka, kb, kp, kq}, h),
    do: {a + ka * h, b + kb * h, p + kp * h, q + kq * h}

  defp rk4(s) do
    k1 = deriv(s)
    k2 = deriv(add(s, k1, @h / 2))
    k3 = deriv(add(s, k2, @h / 2))
    k4 = deriv(add(s, k3, @h))
    {a, b, p, q} = s

    {a + @h / 6 * (elem(k1, 0) + 2 * elem(k2, 0) + 2 * elem(k3, 0) + elem(k4, 0)),
     b + @h / 6 * (elem(k1, 1) + 2 * elem(k2, 1) + 2 * elem(k3, 1) + elem(k4, 1)),
     p + @h / 6 * (elem(k1, 2) + 2 * elem(k2, 2) + 2 * elem(k3, 2) + elem(k4, 2)),
     q + @h / 6 * (elem(k1, 3) + 2 * elem(k2, 3) + 2 * elem(k3, 3) + elem(k4, 3))}
  end

  defp kinetic({a, b, p, q}), do: p * p + 0.5 * q * q + p * q * :math.cos(a - b)
  defp potential({a, b, _, _}), do: -2 * @g * :math.cos(a) - @g * :math.cos(b)

  # The lower bob's place on screen.
  defp tip({a, b, _, _}),
    do: {@cx + @sx * (:math.sin(a) + :math.sin(b)), @cy + @sy * (:math.cos(a) + :math.cos(b))}

  @impl true
  def init(_options) do
    e0 = kinetic(@start) + potential(@start)
    sim = %{s: @start, trail: :queue.new(), len: 0, steps: 0, e0: e0}
    warm = Enum.reduce(1..JSMath.ceil(@warm / @h), sim, fn _, sim -> step(sim) end)
    %{sim: warm, warm: warm, acc: 0, last: 0}
  end

  defp step(%{e0: e0} = sim) do
    s = rk4(sim.s)
    # Hold the energy where it began, so long runs neither die down nor run away.
    k = kinetic(s)
    room = e0 - potential(s)

    s =
      if k > 1.0e-9 and room > 0 do
        f = :math.sqrt(room / k)
        {a, b, p, q} = s
        {a, b, p * f, q * f}
      else
        s
      end

    steps = sim.steps + 1
    sim = %{sim | s: s, steps: steps}
    if rem(steps, @tap) == 0, do: sample(sim, tip(s)), else: sim
  end

  defp sample(%{len: @trail} = sim, point),
    do: %{sim | trail: :queue.in(point, :queue.drop(sim.trail))}

  defp sample(sim, point), do: %{sim | trail: :queue.in(point, sim.trail), len: sim.len + 1}

  @impl true
  def frame(state, t, _env) do
    # Going back in time starts again from the warmed-up swing.
    state = if t < state.last, do: %{state | sim: state.warm, acc: 0, last: 0}, else: state
    acc = state.acc + min(max(t - state.last, 0), 0.1) * @speed
    {sim, acc} = run(state.sim, acc)
    {draw(sim), nil, %{state | sim: sim, acc: acc, last: t}}
  end

  defp run(sim, acc) when acc >= @h, do: run(step(sim), acc - @h)
  defp run(sim, acc), do: {sim, acc}

  defp draw(%{s: s, trail: trail, len: len}) do
    # Oldest first, a segment at a time so a fast swing leaves no gaps.
    grid =
      case :queue.to_list(trail) do
        [] -> %{}
        [first | rest] -> trail(rest, first, 1, len, %{})
      end

    {a, _, _, _} = s
    x1 = @cx + @sx * :math.sin(a)
    y1 = @cy + @sy * :math.cos(a)
    {x2, y2} = tip(s)

    grid =
      grid
      |> rod(@cx, @cy, x1, y1)
      |> rod(x1, y1, x2, y2)
      |> put(@cx - 1, @cy, "(")
      |> put(@cx, @cy, "+")
      |> put(@cx + 1, @cy, ")")
      |> put(x1, y1, "o")
      |> put(x2, y2, "@")

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(grid, r * @cols + c, " ")
      end

    Enum.intersperse(lines, ?\n)
  end

  defp trail([], _prev, _i, _len, grid), do: grid

  defp trail([{x1, y1} = point | rest], {x0, y0}, i, len, grid) do
    ch = elem(@fade, JSMath.floor(i / len * tuple_size(@fade)))

    n =
      case JSMath.ceil(max(abs(x1 - x0), abs(y1 - y0)) * 2) do
        0 -> 1
        n -> n
      end

    grid =
      Enum.reduce(0..(n - 1), grid, fn j, grid ->
        put(grid, x0 + (x1 - x0) * j / n, y0 + (y1 - y0) * j / n, ch)
      end)

    trail(rest, point, i + 1, len, grid)
  end

  defp put(grid, x, y, ch) do
    c = JSMath.round(x)
    r = JSMath.round(y)

    if c >= 0 and c < @cols and r >= 0 and r < @rows,
      do: Map.put(grid, r * @cols + c, ch),
      else: grid
  end

  # A thin rod, one glyph a cell. A shallow rod is a run of dashes on each
  # row, which meets the next row low or high in the cell; a steep one is a
  # bar or a slash a row. A cell is twice as tall as it is wide, so steep
  # means more than one row in two columns.
  defp rod(grid, x0, y0, x1, y1) do
    dx = x1 - x0
    dy = y1 - y0
    up = dx * dy < 0
    slash = if up, do: "/", else: "\\"

    cond do
      abs(dx) > abs(2 * dy) -> shallow(grid, x0, y0, x1, dx, dy, up, slash)
      # Both ends in one place: upstream's NaNs draw nothing.
      dy == 0 -> grid
      true -> steep(grid, x0, y0, y1, dx, dy, slash)
    end
  end

  defp shallow(grid, x0, y0, x1, dx, dy, up, slash) do
    c0 = JSMath.round(min(x0, x1))
    c1 = JSMath.round(max(x0, x1))
    row = fn c -> JSMath.floor(y0 + dy * (min(c1, max(c0, c)) - x0) / dx + 0.5) end

    Enum.reduce(c0..c1//1, grid, fn c, grid ->
      r = row.(c)
      first = row.(c - 1) != r
      last = row.(c + 1) != r

      # Left to right a rising rod comes in low and leaves high; a falling one
      # the other way round.
      ch =
        cond do
          first and last -> slash
          first and up -> "_"
          first -> if row.(c + 2) != r, do: slash, else: "`"
          last and up -> if row.(c - 2) != r, do: slash, else: "'"
          last -> "_"
          true -> "-"
        end

      put(grid, c, r, ch)
    end)
  end

  defp steep(grid, x0, y0, y1, dx, dy, slash) do
    steep = abs(dx / dy) < 0.6

    Enum.reduce(JSMath.round(min(y0, y1))..JSMath.round(max(y0, y1))//1, grid, fn r, grid ->
      x = x0 + dx * (r - y0) / dy
      c = JSMath.floor(x + 0.5)
      put(grid, c, r, if(steep and abs(x - c) < 0.3, do: "|", else: slash))
    end)
  end
end
