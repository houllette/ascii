defmodule AsciiArt.Pieces.Lorenz do
  @moduledoc """
  One lorenz trajectory looping both wings, older loops fading.

  One trajectory of the Lorenz system. The near side of each loop is drawn
  heavier than the far side, old loops fade out, and the view sways.

  Ported from `src/pieces/lorenz.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath

  @meta %AsciiArt.Meta{
    name: "lorenz attractor",
    category: :physics,
    note: "one lorenz trajectory looping both wings, older loops fading",
    cols: 60,
    rows: 22,
    fps: 30
  }

  # The body of the trail; # and @ are kept for its tip.
  @ramp {" ", ".", ":", "-", "=", "+", "*"}
  # Time per integration step, and steps per second of play.
  @dt 0.004
  @rate 125
  # Steps kept on screen, and the newest steps drawn as the bright tip.
  @trail 2400
  @lead 26
  # The view looks this far down onto the attractor, in radians; the turn
  # that shows both wings side by side; how far the view swings either way,
  # in radians, and seconds per swing.
  @tilt 0.3
  @face 2.36
  @sway 0.6
  @sway_t 48
  # Past this share of the frame, rare wide loops are eased in.
  @knee 0.8
  # How fast old loops fade; the far side's weight against the near side's;
  # what each later pass through a cell adds.
  @age 1.5
  @far 0.3
  @pass 0.06

  @cols 60
  @rows 22
  # A typical stretch of trail stands about 33 units tall, centred a little
  # above z = 25; the scale fits that to rows 1 to 20, and the odd wide loop
  # is squeezed into the last cells rather than cut off.
  @half_h (@rows - 3) / 2
  @half_w @cols / 2 - 2.5
  @k 4 * @half_h / 33.5
  @mid 1.3

  @compile {:inline, f: 3, ease: 1}

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    zero = {0.0, 0.0, 0.0}
    trail = :queue.from_list(List.duplicate(zero, @trail))
    sim = %{x: 1, y: 1, z: 1, head: 0, trail: trail}
    sim = Enum.reduce(1..24_000, sim, fn _, sim -> step(sim) end)

    weights = List.to_tuple(for n <- 0..(@trail - 1), do: :math.pow(n / @trail, @age))

    Map.merge(sim, %{
      weights: weights,
      ct: :math.cos(@tilt),
      st: :math.sin(@tilt),
      last: 0,
      owed: 0
    })
  end

  # One RK4 step of sigma = 10, rho = 28, beta = 8/3.
  defp f(x, y, z), do: {10 * (y - x), x * (28 - z) - y, x * y - 8 / 3 * z}

  defp step(%{x: x, y: y, z: z} = sim) do
    {a1, b1, c1} = f(x, y, z)
    {a2, b2, c2} = f(x + @dt / 2 * a1, y + @dt / 2 * b1, z + @dt / 2 * c1)
    {a3, b3, c3} = f(x + @dt / 2 * a2, y + @dt / 2 * b2, z + @dt / 2 * c2)
    {a4, b4, c4} = f(x + @dt * a3, y + @dt * b3, z + @dt * c3)
    x = x + @dt / 6 * (a1 + 2 * a2 + 2 * a3 + a4)
    y = y + @dt / 6 * (b1 + 2 * b2 + 2 * b3 + b4)
    z = z + @dt / 6 * (c1 + 2 * c2 + 2 * c3 + c4)

    # The trail is a Float32Array ring, kept here oldest first.
    point = {JSMath.fround(x), JSMath.fround(y), JSMath.fround(z)}
    trail = :queue.in(point, :queue.drop(sim.trail))
    %{sim | x: x, y: y, z: z, head: rem(sim.head + 1, @trail), trail: trail}
  end

  defp ease(a) do
    m = abs(a)

    if m <= @knee,
      do: a,
      else: JSMath.sign(a) * (@knee + (1 - @knee) * :math.tanh((m - @knee) / (1 - @knee)))
  end

  @impl true
  def frame(state, t, _env) do
    owed = state.owed + min(max(t - state.last, 0), 0.1) * @rate
    {state, owed} = run(state, owed)
    state = %{state | owed: owed, last: t}

    turn = @face + @sway * :math.sin(2 * :math.pi() * t / @sway_t)
    c = :math.cos(turn)
    s = :math.sin(turn)
    points = :queue.to_list(state.trail)

    # How deep the trail is from this side sets the depth scale, so the near
    # edge of each wing reads heavier even when the wings face the eye. The
    # sum runs in the ring's own order.
    {older, newer} = Enum.split(points, @trail - state.head)

    sum =
      Enum.reduce(newer ++ older, 0, fn {px, py, _}, sum ->
        v = px * s + py * c
        sum + v * v
      end)

    deep = 1 / (3 * :math.sqrt(sum / @trail))
    view = {c, s, state.ct, state.st, deep}

    {ink, tips, hc, _, _} =
      Enum.reduce(points, {%{}, MapSet.new(), 0, -1, 0}, fn point, acc ->
        plot(point, acc, view, state.weights)
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for q <- 0..(@cols - 1) do
          i = r * @cols + q

          cond do
            i == hc -> "@"
            MapSet.member?(tips, i) -> "#"
            true -> elem(@ramp, min(tuple_size(@ramp) - 1, floor(Map.get(ink, i, 0) * 7)))
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end

  defp run(state, owed) when owed >= 1, do: run(step(state), owed - 1)
  defp run(state, owed), do: {state, owed}

  defp plot({px, py, pz}, {ink, tips, hc, prev, n}, {c, s, ct, st, deep}, weights) do
    u = px * c - py * s
    # Depth, positive is away.
    v = px * s + py * c
    h = (pz - 25) * ct - v * st
    col = JSMath.round(@cols / 2 - 0.5 + ease(u * @k / @half_w) * @half_w)
    row = JSMath.round(@rows / 2 - 0.5 - ease((h - @mid) * @k * 0.5 / @half_h) * @half_h)

    if col < 0 or col >= @cols or row < 0 or row >= @rows do
      {ink, tips, hc, prev, n + 1}
    else
      q = row * @cols + col
      # Recent and near is heavy; old or far is faint, and the oldest is gone.
      # A cell crossed more than once gains a little for each later pass.
      near = min(1, max(0, 0.5 - v * deep))
      w = elem(weights, n) * (@far + (1 - @far) * near * near)

      ink =
        if q == prev do
          ink
        else
          was = Map.get(ink, q, 0)
          Map.put(ink, q, JSMath.fround(max(was, w) + if(was > 0, do: @pass, else: 0)))
        end

      tips = if n >= @trail - @lead, do: MapSet.put(tips, q), else: tips
      {ink, tips, q, q, n + 1}
    end
  end
end
