defmodule Ascii.Pieces.Sparks do
  @moduledoc """
  An angle grinder throwing sparks that arc, skip and cool.

  An angle grinder biting into a steel plate. Sparks leave the cut in a
  tight hot cone, arc under gravity, skip on the plate and cool.

  Ported from `src/pieces/sparks.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  import Bitwise

  @meta %Ascii.Meta{
    name: "sparks",
    category: :effects,
    note: "an angle grinder throwing sparks that arc, skip and cool",
    cols: 64,
    rows: 20,
    fps: 30
  }

  @cols 64
  # The plate's top face, in rows: sparks skip along the row above it.
  @floor 17
  # The disc's radius, in rows (twice that in columns), and how far it cuts
  # into the plate.
  @rd 3.7
  @sink 0.3
  # The disc's centre.
  @dx 24
  @dy 17 - 3.7 + 0.3
  # Gravity, rows a second squared.
  @g 30
  # Sparks a second at full pressure.
  @rate 320
  # The longest a spark glows, seconds.
  @life 1.3
  # Speed kept up and along at each bounce.
  @bounce 0.3
  @skid 0.55
  @shade {" ", "░", "▒", "▓", "█"}
  # Quadrant blocks by which quarters of a cell are bright: top left 1, top
  # right 2, bottom left 4, bottom right 8.
  @quad {" ", "▘", "▝", "▀", "▖", "▌", "▞", "▛", "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█"}
  @two_pi 2 * :math.pi()

  @compile {:inline, hash: 2, u32: 1, umul: 2, mark: 5}

  @impl true
  def meta, do: @meta

  # Where the rim comes up out of the cut: the sparks leave from there.
  defp ex, do: @dx + 2 * :math.sqrt(@rd * @rd - (@rd - @sink) * (@rd - @sink))

  @impl true
  def init(_options) do
    ex = ex()

    tool =
      for r <- 0..(@floor - 1) do
        for c <- 0..(@cols - 1) do
          samples =
            for q <- 0..3, do: tool(c + 0.25 + 0.5 * band(q, 1), r + 0.25 + 0.5 * bsr(q, 1))

          if Enum.any?(samples, &match?({:label, _}, &1)),
            do: {:dynamic, samples},
            else: {:static, grinder(samples, false), grinder(samples, true)}
        end
      end

    %{ex: ex, tool: tool, cache: %{}}
  end

  defp u32(x), do: band(x, 0xFFFFFFFF)

  defp umul(a, b),
    do:
      band(band(a, 0xFFFF) * b + bsl(band(bsr(a, 16) * band(b, 0xFFFF), 0xFFFF), 16), 0xFFFFFFFF)

  defp hash(i, s) do
    h = bxor(umul(bxor(u32(i), 0x9E3779B9), 0x85EBCA6B), umul(u32(s + 1), 0xC2B2AE35))
    h = umul(bxor(h, bsr(h, 15)), 0x2C1B3C6D)
    h = umul(bxor(h, bsr(h, 12)), 0x297A2D39)
    bxor(h, bsr(h, 15)) / 4_294_967_296
  end

  # Where a spark is at age a: {x, y, vx, vy, bounces}, rows down, vy upward.
  # It hops along the plate, losing speed each time it lands.
  defp at(ex, {_t0, vx, vy, _life}, a), do: hop(ex, vx, vy, a, 0)

  defp hop(_x, _vx, _vy, _a, 3), do: nil

  defp hop(x, vx, vy, a, b) do
    tt = 2 * vy / @g

    if a < tt,
      do: {x + vx * a, @floor - 0.5 - vy * a + @g * a * a / 2, vx, vy - @g * a, b},
      else: hop(x + vx * tt, vx * @skid, vy * @bounce, a - tt, b + 1)
  end

  # The grinder at a point in cells: a shade (0 to 1), -1 for none, or
  # {:label, angle} where the turning label decides. The disc in front, then
  # its guard, the side handle and the motor body.
  defp tool(x, y) do
    # In columns, y up; d in rows.
    xx = x - @dx
    yy = (@dy - y) * 2
    d = JSMath.hypot(xx, yy) / 2
    ang = :math.atan2(yy, xx)

    cond do
      d < @rd ->
        disc(d, ang)

      # The guard wraps the half of the disc toward the operator.
      d > @rd + 0.45 and d < @rd + 1.35 and ang > 0.75 and ang < 3.8 ->
        if(d < @rd + 0.9, do: 1.0, else: 0.7)

      true ->
        handle(x, y)
    end
  end

  # The arbor nut, the flange, the rim, and the printed label: one bright arc
  # that turns with the disc.
  defp disc(d, _ang) when d < 0.5, do: 0.1
  defp disc(d, _ang) when d < 1.05, do: 0.9
  defp disc(d, _ang) when d > @rd - 0.55, do: 1.0
  defp disc(d, ang) when d > 1.7 and d < 2.6, do: {:label, ang}
  defp disc(_d, _ang), do: 0.3

  # The side handle stands up from the gearhead: a knurled grip with a
  # rounded end on a short stem, lit from the left.
  defp handle(x, y) do
    hx = x - (@dx - 3.5)
    top = 1.2
    grip = 6.6
    base = @dy - @rd - 1.2

    if y > top and y < base and abs(hx) < if(y < grip, do: 1.6, else: 0.9) do
      cond do
        # The rounded end.
        y < top + 0.6 and abs(hx) > 1.1 -> -1
        hx > 0.3 -> 0.4
        y > top + 1 and y < grip - 0.5 and rem(floor(y), 2) == 0 -> 0.7
        true -> 0.95
      end
    else
      motor(x, y)
    end
  end

  # The motor body, a cylinder lit from above, vented near the back.
  defp motor(x, y) do
    by = (y - (@dy - 0.4)) / 2

    cond do
      not (x > 1 and x < @dx and abs(by) < 1) -> -1
      # The rounded end cap.
      x < 2.5 and abs(by) > 0.55 -> -1
      x > 4 and x < 11 and abs(by + 0.1) < 0.4 and rem(floor(x), 2) == 0 -> 0.1
      by < -0.5 -> 0.95
      by < 0.1 -> 0.75
      by < 0.55 -> 0.45
      true -> 0.25
    end
  end

  # A cell of the grinder from its four samples: bright parts as quadrant
  # blocks for a crisp outline, dim ones as shade. nil where it misses.
  defp grinder(samples, paper) do
    {mask, hit, sum, lit, _} =
      Enum.reduce(samples, {0, 0, 0, 0, 0}, fn
        v, acc when v < 0 ->
          put_elem(acc, 4, elem(acc, 4) + 1)

        v, {mask, hit, sum, lit, q} when v >= 0.6 ->
          {bor(mask, bsl(1, q)), hit + 1, sum, lit + v, q + 1}

        v, {mask, hit, sum, lit, q} ->
          {mask, hit + 1, sum + v, lit, q + 1}
      end)

    cond do
      hit == 0 -> nil
      paper and hit < 2 -> " "
      paper -> elem(@shade, max(1, 4 - JSMath.round((sum + lit) / hit * 4)))
      mask == 15 -> if(lit / 4 > 0.9, do: "█", else: "▓")
      mask != 0 -> elem(@quad, mask)
      true -> elem(@shade, JSMath.round(sum / hit * 4))
    end
  end

  # Spark i: when it left the cut, its speed, angle and how long it glows.
  # Most leave close along the tangent of the rim; the grinder bites harder
  # and softer by turns.
  defp spark(i) do
    t0 = (i + hash(i, 1)) / @rate
    press = 0.72 + 0.28 * :math.sin(t0 * 1.9) * :math.sin(t0 * 0.7 + 1)

    if hash(i, 2) > press do
      nil
    else
      deg = 4 + 30 * ((hash(i, 3) + hash(i, 6)) / 2)
      # A few kicked higher off the guard.
      deg = if hash(i, 7) < 0.1, do: deg + 25 * hash(i, 8), else: deg
      ang = deg * :math.pi() / 180
      v = 34 + 44 * hash(i, 4)
      life = 0.3 + (@life - 0.3) * :math.pow(hash(i, 5), 0.8)
      {t0, v * :math.cos(ang), v * :math.sin(ang) / 2, life}
    end
  end

  defp along(vx, vy) do
    a = :math.atan2(2 * vy, vx) * 180 / :math.pi()

    cond do
      a > 60 or a < -60 -> "|"
      a > 20 -> "/"
      a < -20 -> "\\"
      true -> "-"
    end
  end

  # Heat adds up in a Float32Array; the hottest spark in a cell draws it.
  defp mark(cells, c, r, h, ch) when c >= 0 and c < @cols and r >= 0 and r < @floor do
    k = r * @cols + c

    case cells do
      %{^k => {heat, top, old}} ->
        heat = JSMath.fround(heat + h)

        if h > top,
          do: %{cells | k => {heat, JSMath.fround(h), ch}},
          else: %{cells | k => {heat, top, old}}

      _ ->
        if h > 0,
          do: Map.put(cells, k, {JSMath.fround(h), JSMath.fround(h), ch}),
          else: Map.put(cells, k, {JSMath.fround(h), 0.0, " "})
    end
  end

  defp mark(cells, _c, _r, _h, _ch), do: cells

  @impl true
  def frame(%{ex: ex, tool: tool, cache: cache} = state, t, env) do
    lo = floor((t - @life) * @rate) - 1
    hi = floor(t * @rate)
    cache = Map.reject(cache, fn {i, _} -> i < lo or i > hi end)

    {cells, cache} =
      Enum.reduce(lo..hi//1, {%{}, cache}, fn i, {cells, cache} ->
        cache = Map.put_new_lazy(cache, i, fn -> spark(i) end)
        {fly(cells, ex, Map.fetch!(cache, i), t), cache}
      end)

    paper = env.paper
    # The bottom of the disc runs toward the spray.
    spin = t * 2 * :math.pi() * 0.6
    # The bite: white heat where the rim comes out of the cut.
    bite = if hash(floor(t * 30), 9) < 0.5, do: "@", else: "#"
    bite_c = floor(ex)

    lines =
      for {row, r} <- Enum.with_index(tool) do
        for {cell, c} <- Enum.with_index(row) do
          if r == @floor - 1 and c == bite_c do
            bite
          else
            k = r * @cols + c

            case grinder_at(cell, paper, spin) do
              nil -> spray(Map.get(cells, k))
              ch -> ch
            end
          end
        end
      end

    # The plate: a lit top edge over its front face.
    plate = [
      String.duplicate("▄", @cols),
      String.duplicate(elem(@shade, 2), @cols),
      String.duplicate(elem(@shade, if(paper, do: 3, else: 1)), @cols)
    ]

    {Enum.intersperse(lines ++ plate, ?\n), nil, %{state | cache: cache}}
  end

  defp grinder_at({:static, ink, _paper}, false, _spin), do: ink
  defp grinder_at({:static, _ink, paper}, true, _spin), do: paper

  defp grinder_at({:dynamic, samples}, paper, spin) do
    samples
    |> Enum.map(fn
      {:label, ang} ->
        k = JSMath.mod(JSMath.mod(ang - spin, @two_pi) + @two_pi, @two_pi)
        if k < 1.3, do: 0.8, else: 0.3

      v ->
        v
    end)
    |> grinder(paper)
  end

  # Where many hot sparks crowd, at the bite, the spray burns solid.
  defp spray(nil), do: " "
  defp spray({heat, _top, _ch}) when heat > 4, do: "#"
  defp spray({heat, _top, _ch}) when heat > 1.8, do: "*"
  defp spray({_heat, _top, ch}), do: ch

  defp fly(cells, _ex, nil, _t), do: cells

  defp fly(cells, ex, {t0, _vx, _vy, life} = s, t) do
    a = t - t0

    with true <- a >= 0 and a <= life,
         {x, y, vx, vy, b} <- at(ex, s, a) do
      # Landing on the plate cools it.
      h = :math.pow(1 - a / life, 1.4) * if(b != 0, do: 0.5, else: 1)
      # In flight, a hot spark draws a streak back along its path.
      cells = if b == 0 and h > 0.35, do: streak(cells, ex, s, a, h, vx, vy), else: cells

      ch =
        cond do
          h > 0.75 -> "*"
          h > 0.5 -> "+"
          h > 0.25 -> "·"
          true -> "."
        end

      mark(cells, floor(x), floor(y), h, ch)
    else
      _ -> cells
    end
  end

  defp streak(cells, ex, s, a, h, vx, vy) do
    n = JSMath.ceil(JSMath.hypot(vx, 2 * vy) * 0.04 * h)
    ch = along(vx, vy)

    Enum.reduce(n..1//-1, cells, fn k, cells ->
      {qx, qy, _, _, _} = at(ex, s, max(0, a - k / n * 0.04 * h))
      mark(cells, floor(qx), floor(qy), h * 0.45, ch)
    end)
  end
end
