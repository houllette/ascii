defmodule AsciiArt.Pieces.FlowField do
  @moduledoc """
  Particle trails gathering into winding, merging streams.

  Particles carried left to right by a smooth noise field whose currents
  pull them together, so their fading trails gather into a few winding
  streams that merge and part as the field slowly changes.

  Ported from `src/pieces/flow-field.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "flow field",
    category: :generative,
    note: "particle trails gathering into winding, merging streams",
    cols: 64,
    rows: 22,
    fps: 20
  }

  # Currents across the field.
  @streams 4
  # Particles let go from the left edge a second.
  @rate 16
  # Cell widths a second.
  @speed 9
  # Seconds for a trail to fade to about a third.
  @fade 1.6
  # How far a current wanders up and down, in cell widths.
  @bend 12
  # Noise cycles per cell width along a current.
  @scale 0.085
  # How hard a current draws particles in, per cell width.
  @pull 0.22
  # How far a current's pull is felt, in cell widths.
  @reach 7
  # How fast the currents change.
  @drift 0.04
  # The steepest heading off the horizontal, in radians.
  @turn 1.2
  # Seconds simulated before the first frame.
  @warm 9

  # The field in cell widths; a row is two of them tall.
  @w 64
  @h 44
  @half @h / 2
  @span @h / 2 - 3

  @compile {:inline, u32: 1, umul: 2, hash: 3, ease: 1, at: 2}

  @impl true
  def meta, do: @meta

  defp u32(x), do: band(x, 0xFFFFFFFF)

  defp umul(a, b),
    do:
      band(band(a, 0xFFFF) * b + bsl(band(bsr(a, 16) * band(b, 0xFFFF), 0xFFFF), 16), 0xFFFFFFFF)

  # A fixed number in [0, 1) for each lattice point.
  defp hash(i, j, k) do
    h = bxor(bxor(umul(u32(i), 0x27D4EB2D), umul(u32(j), 0x165667B1)), umul(k, 0x9E3779B1))
    h = umul(bxor(h, bsr(h, 15)), 0x85EBCA77)
    bxor(h, bsr(h, 13)) / 4_294_967_296
  end

  defp ease(f), do: f * f * f * (f * (f * 6 - 15) + 10)

  @impl true
  def init(_options) do
    steep = :math.atan(2)
    dt = 1 / @meta.fps

    sim = %{
      rand: Int32.to_int32(0x5EED),
      ps: [],
      ink: %{},
      clock: 0,
      due: 0,
      # A glyph for each direction, from the true angle on screen: a cell is
      # twice as tall as it is wide, so / and \ stand at about 63 degrees.
      flat: steep / 2,
      upright: (:math.pi() / 2 + steep) / 2
    }

    sim = Enum.reduce(1..(@warm * @meta.fps), sim, fn _, sim -> step(sim, dt) end)
    Map.put(sim, :last, 0)
  end

  # Per current, the parts of its noise that only depend on the time z:
  # {k, its place across the field, its offset along the noise, the noise
  # row, and the ease between rows}.
  defp lanes(z) do
    for k <- 0..(@streams - 1) do
      zk = z + k * 3.1
      j = floor(zk)
      {k, ((k + 0.5) / @streams - 0.5) * @h, k * 7.3, j, ease(zk - j)}
    end
  end

  # Where current k runs at column xx: wandering freely mid-frame, eased back
  # in near the top and bottom.
  defp at({k, base, offset, j, v}, xx) do
    x = xx * @scale + offset
    i = floor(x)
    u = ease(x - i)
    h00 = hash(i, j, k)
    h01 = hash(i, j + 1, k)
    a = h00 + (hash(i + 1, j, k) - h00) * u
    b = h01 + (hash(i + 1, j + 1, k) - h01) * u
    y = base + @bend * (2 * (a + (b - a) * v) - 1)
    @half + @span * :math.tanh(y / @span)
  end

  # Where each current runs at column x, and its slope there, as the
  # Float32Arrays hold them.
  defp current(lane, x), do: {JSMath.fround(at(lane, x)), current_slope(lane, x)}

  defp current_slope(lane, x),
    do: JSMath.fround(at(lane, x + 0.5) - at(lane, x - 0.5))

  # The heading of a particle in lane `o` at (x, y): along the nearby
  # currents, and in towards them.
  defp heading(lanes, x, y, o) do
    {num, den, best, _} =
      Enum.reduce(lanes, {0, 1.0e-9, 0, 1.0e9}, fn lane, {num, den, best, near} ->
        {yk, sk} = current(lane, x)
        d = yk + o - y
        q = d / @reach
        w = :math.exp(-(q * q))
        pulled = sk + @pull * d

        if abs(d) < near,
          do: {num + w * pulled, den + w, pulled, abs(d)},
          else: {num + w * pulled, den + w, best, near}
      end)

    slope = if den > 1.0e-4, do: num / den, else: best
    max(-@turn, min(@turn, :math.atan(slope)))
  end

  defp glyph(sim, a) do
    tilt = abs(a)

    cond do
      tilt < sim.flat -> "-"
      tilt > sim.upright -> "|"
      # y grows downward
      a > 0 -> "\\"
      true -> "/"
    end
  end

  defp step(sim, dt) do
    clock = sim.clock + dt
    keep = :math.exp(-dt / @fade)

    # Ink fades; a cell faded past the faintest glyph is gone until marked again.
    ink =
      Enum.reduce(sim.ink, %{}, fn {k, {v, g}}, ink ->
        v = JSMath.fround(v * keep)
        if v > 0.14, do: Map.put(ink, k, {v, g}), else: ink
      end)

    lanes = lanes(clock * @drift)
    {ps, due, rand} = spawn(sim.ps, sim.due - dt, sim.rand, lanes)

    # Newest first, as upstream walks its array from the end.
    {ps, ink} =
      Enum.reduce(ps, {[], ink}, fn {px, py, o}, {kept, ink} ->
        a = heading(lanes, px, py, o)
        dx = :math.cos(a) * @speed * dt
        dy = :math.sin(a) * @speed * dt
        n = max(1, ceil(JSMath.hypot(dx, dy * 0.5) * 1.5))
        g = glyph(sim, a)

        ink =
          Enum.reduce(1..n, ink, fn s, ink -> mark(ink, px + dx * s / n, py + dy * s / n, g) end)

        x = px + dx
        y = py + dy

        if x >= @w or y < 0 or y >= @h,
          do: {kept, ink},
          else: {[{x, y, o} | kept], ink}
      end)

    %{sim | clock: clock, due: due, rand: rand, ps: Enum.reverse(ps), ink: ink}
  end

  # New particles come in at the left edge: most near a current, some
  # anywhere, to show the field drawing them in.
  defp spawn(ps, due, rand, lanes) when due <= 0 do
    {r, rand} = Int32.mulberry32(rand)

    {y, rand} =
      if r < 0.75 do
        {r1, rand} = Int32.mulberry32(rand)
        {r2, rand} = Int32.mulberry32(rand)
        lane = Enum.at(lanes, floor(r1 * @streams))
        {JSMath.fround(at(lane, 0)) + (r2 - 0.5) * 8, rand}
      else
        {r1, rand} = Int32.mulberry32(rand)
        {2 + r1 * (@h - 4), rand}
      end

    {r, rand} = Int32.mulberry32(rand)
    spawn([{0, y, (r - 0.5) * 3.2} | ps], due + 1 / @rate, rand, lanes)
  end

  defp spawn(ps, due, rand, _lanes), do: {ps, due, rand}

  defp mark(ink, x, y, g) do
    %{cols: cols, rows: rows} = @meta
    c = floor(x)
    r = floor(y / 2)

    if c < 0 or c >= cols or r < 0 or r >= rows,
      do: ink,
      else: Map.put(ink, r * cols + c, {1.0, g})
  end

  @impl true
  def frame(sim, t, _env) do
    %{cols: cols, rows: rows} = @meta
    dt = min(0.1, max(0, t - sim.last))
    sim = %{sim | last: t}
    sim = if dt > 0, do: step(sim, dt), else: sim
    ink = sim.ink

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          k = r * cols + c

          case ink do
            %{^k => {v, g}} -> shade(v, g)
            _ -> " "
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, sim}
  end

  defp shade(v, g) when v > 0.5, do: g
  defp shade(v, _g) when v > 0.27, do: "·"
  defp shade(v, _g) when v > 0.14, do: "."
  defp shade(_v, _g), do: " "
end
