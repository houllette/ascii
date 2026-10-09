defmodule Ascii.Pieces.ReactionDiffusion do
  @moduledoc """
  Gray-scott spots and stripes dying back and growing out.

  A Gray-Scott reaction whose spots on the left give way to stripes on the
  right. Every few seconds the kill rate rises, the pattern dies back to a
  few survivors, and they grow out again.

  Ported from `src/pieces/reaction-diffusion.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}

  @meta %Ascii.Meta{
    name: "reaction diffusion",
    category: :generative,
    note: "gray-scott spots and stripes dying back and growing out",
    cols: 60,
    rows: 24,
    fps: 20
  }

  # The grid, two cells to a character so they are square.
  @w 60
  @h 48
  # Feed and kill rates.
  @spots {0.0367, 0.0649}
  @stripes {0.03, 0.057}
  # Diffusion.
  @du 0.45
  @dv 0.225
  # Reaction steps a second.
  @rate 1000
  # Steps from one die back to the next.
  @cycle 8000
  # The kill rate's rise over a cycle, and its height.
  @back {0.1, 0.25, 0.35, 0.48}
  @bump 0.012
  # Seeds scattered at the start, and steps run before the first frame.
  @seeds 48
  @warm 1200
  # Concentration of the second chemical. Below the floor is bare ground;
  # above it a steep curve, so every feature has a crisp edge. The pattern is
  # the ink, so it keeps its ramp on paper.
  @ramp {"-", "=", "*", "#", "%", "@"}
  @floor 0.12
  @top 0.28

  # The grid is a list of rows, each a list of the two chemicals interleaved,
  # [u, v, u, v, ...], with the last cell copied before the first and the
  # first after the last, so a step walks each row once with its neighbours
  # in reach. Every value is rounded to single precision as upstream's
  # Float32Arrays store it: Veltkamp's split at 2^29 + 1 rounds a double to
  # the 24 bits of a single, ties to even, as Math.fround does, wherever the
  # result is a normal single, at a third of the cost; zero keeps its sign
  # and smaller values go the long way.
  @split 536_870_913.0
  @tiny 1.1754943508222875e-38

  @compile {:inline, f32: 1}

  @impl true
  def meta, do: @meta

  defp f32(x) do
    g = @split * x
    y = g + (x - g)

    cond do
      y >= @tiny or y <= -@tiny ->
        y

      x == 0.0 ->
        x

      true ->
        <<r::float-32>> = <<x::float-32>>
        r
    end
  end

  defp smooth(a, b, x) do
    s = max(0, min(1, (x - a) / (b - a)))
    s * s * (3 - 2 * s)
  end

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    {spot_f, spot_k} = @spots
    {stripe_f, stripe_k} = @stripes

    # Feed and kill across, as {feed, feed + kill}.
    coef =
      Enum.flat_map(0..(@w - 1), fn x ->
        s = smooth(0.1, 0.9, (1 + :math.sin(2 * :math.pi() * (x + 0.5) / @w)) / 2)
        feed = JSMath.fround(stripe_f + (spot_f - stripe_f) * s)
        kill = JSMath.fround(stripe_k + (spot_k - stripe_k) * s)
        [feed, feed + kill]
      end)

    # The frame fades toward its edges, so the pattern thins out there.
    fade =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          ax = abs((c + 0.5) / cols - 0.5) * 2
          ay = abs((r + 0.5) / rows - 0.5) * 2
          cube = JSMath.cbrt(:math.pow(ax, 3) + :math.pow(ay, 3))
          JSMath.fround(1 - 0.6 * smooth(0.55, 1, cube))
        end
      end

    blank = List.duplicate(1.0, @w) |> Enum.flat_map(&[&1, 0.0]) |> List.to_tuple()
    grid = List.to_tuple(List.duplicate(blank, @h))

    {grid, rand} =
      Enum.reduce(1..@seeds, {grid, Int32.to_int32(5)}, fn _, {grid, rand} ->
        seed_random(grid, rand)
      end)

    sim = %{
      rows: pad_rows(grid),
      coef: Enum.split(coef, 2),
      fade: fade,
      bite: nil,
      rand: rand,
      n: 0,
      cycle: -1
    }

    run(sim, @warm)
  end

  defp seed_random(grid, rand) do
    {x, rand} = Int32.mulberry32(rand)
    {y, rand} = Int32.mulberry32(rand)
    {seed(grid, floor(x * @w), floor(y * @h)), rand}
  end

  defp seed(grid, cx, cy) do
    for dy <- -2..2, dx <- -2..2, reduce: grid do
      grid ->
        y = rem(cy + dy + @h, @h)
        x = rem(cx + dx + @w, @w)
        row = elem(grid, y) |> put_elem(2 * x, 0.5) |> put_elem(2 * x + 1, 0.25)
        put_elem(grid, y, row)
    end
  end

  # A tuple of rows of interleaved values to the padded lists, and back.
  defp pad_rows(grid) do
    grid
    |> Tuple.to_list()
    |> Enum.map(fn row ->
      [u0, v0 | _] = list = Tuple.to_list(row)
      [elem(row, 2 * @w - 2), elem(row, 2 * @w - 1) | list ++ [u0, v0]]
    end)
  end

  defp unpad_rows(rows) do
    rows
    |> Enum.map(fn [_, _ | row] -> row |> Enum.take(2 * @w) |> List.to_tuple() end)
    |> List.to_tuple()
  end

  # Each die back is uneven: a smooth random field, new every cycle, sets how
  # hard it bites where, so the survivors fall differently each time.
  defp reshape(rand) do
    {waves, rand} = Enum.map_reduce(1..3, rand, fn _, rand -> wave(rand) end)

    bite =
      for y <- 0..(@h - 1) do
        for x <- 0..(@w - 1) do
          s =
            Enum.reduce(waves, 0, fn {kx, ky, p}, s ->
              s + :math.cos(2 * :math.pi() * (kx * x / @w + ky * y / @h) + p)
            end)

          JSMath.fround(1 + s / 6)
        end
      end

    {bite, rand}
  end

  defp wave(rand) do
    {a, rand} = Int32.mulberry32(rand)
    {b, rand} = Int32.mulberry32(rand)
    kx = floor(a * 5) - 2
    ky = floor(b * 5) - 2

    if kx == 0 and ky == 0 do
      wave(rand)
    else
      {p, rand} = Int32.mulberry32(rand)
      {{kx, ky, p * 6.283}, rand}
    end
  end

  defp bump(p) do
    {b0, b1, b2, b3} = @back
    @bump * smooth(b0, b1, p) * (1 - smooth(b2, b3, p))
  end

  defp run(%{n: n} = sim, want) when n < want, do: sim |> step() |> run(want)
  defp run(sim, _want), do: sim

  defp step(sim) do
    n = sim.n
    # The cycle starts on the first frame.
    k = floor((n - @warm) / @cycle)

    sim =
      if k != sim.cycle do
        {bite, rand} = reshape(sim.rand)
        %{sim | cycle: k, bite: bite, rand: rand}
      else
        sim
      end

    p = (n - @warm) / @cycle - k
    b = bump(p)
    [first | _] = rows = sim.rows
    padded = [List.last(rows) | rows] ++ [first]

    rows =
      if b == 0,
        do: step_rows(padded, sim.coef),
        else: step_rows(padded, sim.coef, sim.bite, b)

    sim = %{sim | rows: rows, n: n + 1}

    # Should a die back ever take everything, start again from a few seeds.
    if p < elem(@back, 3) and p + 1 / @cycle >= elem(@back, 3) and total(rows) < 8,
      do: reseed(sim),
      else: sim
  end

  defp total(rows) do
    Enum.reduce(rows, 0, fn [_, _ | row], s -> sum_v(row, s, @w) end)
  end

  defp sum_v(_row, s, 0), do: s
  defp sum_v([_u, v | row], s, k), do: sum_v(row, s + v, k - 1)

  defp reseed(sim) do
    {grid, rand} =
      Enum.reduce(1..4, {unpad_rows(sim.rows), sim.rand}, fn _, {grid, rand} ->
        seed_random(grid, rand)
      end)

    %{sim | rows: pad_rows(grid), rand: rand}
  end

  # The first cell of each row is stepped on its own, so the row's padding
  # is at hand when it is put back in order.
  defp step_rows([m | [z, p | _] = rest], {head, tail} = coef) do
    [v0, u0] = first = row(m, z, p, head, [])
    [_, _ | m1] = m
    [_, _ | z1] = z
    [_, _ | p1] = p
    [pad(row(m1, z1, p1, tail, first), u0, v0) | step_rows(rest, coef)]
  end

  defp step_rows(_rest, _coef), do: []

  defp step_rows([m | [z, p | _] = rest], {head, tail} = coef, [[b0 | bite] | bites], b) do
    [v0, u0] = first = row(m, z, p, head, [b0], b, [])
    [_, _ | m1] = m
    [_, _ | z1] = z
    [_, _ | p1] = p
    [pad(row(m1, z1, p1, tail, bite, b, first), u0, v0) | step_rows(rest, coef, bites, b)]
  end

  defp step_rows(_rest, _coef, _bites, _b), do: []

  # The new row comes out last cell first: put it in order, and pad it.
  defp pad([v_last, u_last | _] = acc, u_first, v_first),
    do: [u_last, v_last | :lists.reverse(acc, [u_first, v_first])]

  # One row of the step, from the rows above (m), at (z) and below (p); a, b
  # and c are the cells left of, at and right of the one being stepped.
  defp row(
         [uma, vma | [umb, vmb, umc, vmc | _] = m],
         [u0a, v0a | [u, v, u0c, v0c | _] = z],
         [upa, vpa | [upb, vpb, upc, vpc | _] = p],
         [f, fk | coef],
         acc
       )
       when is_float(uma) and is_float(vma) and is_float(umb) and is_float(vmb) and
              is_float(umc) and is_float(vmc) and is_float(u0a) and is_float(v0a) and
              is_float(u) and is_float(v) and is_float(u0c) and is_float(v0c) and
              is_float(upa) and is_float(vpa) and is_float(upb) and is_float(vpb) and
              is_float(upc) and is_float(vpc) and is_float(f) and is_float(fk) do
    lu = 0.2 * (umb + upb + u0a + u0c) + 0.05 * (uma + umc + upa + upc) - u
    lv = 0.2 * (vmb + vpb + v0a + v0c) + 0.05 * (vma + vmc + vpa + vpc) - v
    uvv = u * v * v
    u2 = f32(u + @du * lu - uvv + f * (1.0 - u))
    v2 = f32(v + @dv * lv + uvv - fk * v)
    row(m, z, p, coef, [v2, u2 | acc])
  end

  defp row(_m, _z, _p, [], acc), do: acc

  # The same while the kill rate is raised, by b where it bites hardest. (f
  # and b go unchecked here, to keep the guard within bounds; arithmetic with
  # a float checks them anyway.)
  defp row(
         [uma, vma | [umb, vmb, umc, vmc | _] = m],
         [u0a, v0a | [u, v, u0c, v0c | _] = z],
         [upa, vpa | [upb, vpb, upc, vpc | _] = p],
         [f, fk | coef],
         [bite | bites],
         b,
         acc
       )
       when is_float(uma) and is_float(vma) and is_float(umb) and is_float(vmb) and
              is_float(umc) and is_float(vmc) and is_float(u0a) and is_float(v0a) and
              is_float(u) and is_float(v) and is_float(u0c) and is_float(v0c) and
              is_float(upa) and is_float(vpa) and is_float(upb) and is_float(vpb) and
              is_float(upc) and is_float(vpc) and is_float(fk) and is_float(bite) do
    lu = 0.2 * (umb + upb + u0a + u0c) + 0.05 * (uma + umc + upa + upc) - u
    lv = 0.2 * (vmb + vpb + v0a + v0c) + 0.05 * (vma + vmc + vpa + vpc) - v
    uvv = u * v * v
    u2 = f32(u + @du * lu - uvv + f * (1.0 - u))
    v2 = f32(v + @dv * lv + uvv - (fk + b * bite) * v)
    row(m, z, p, coef, bites, b, [v2, u2 | acc])
  end

  defp row(_m, _z, _p, [], _bites, _b, acc), do: acc

  @impl true
  def frame(sim, t, _env) do
    want = @warm + floor(t * @rate)
    # A long pause skips ahead rather than stalls.
    sim = if want - sim.n > @rate / 5, do: %{sim | n: want - ceil(@rate / 5)}, else: sim
    sim = run(sim, want)

    lines =
      sim.rows
      |> Enum.chunk_every(2)
      |> Enum.zip_with(sim.fade, fn [[_, _ | a], [_, _ | b]], fade -> line(a, b, fade) end)

    {Enum.intersperse(lines, ?\n), nil, sim}
  end

  defp line([_ua, va | a], [_ub, vb | b], [fade | fades]) do
    val = (va + vb) / 2 * fade
    [glyph(val) | line(a, b, fades)]
  end

  defp line(_a, _b, []), do: []

  defp glyph(val) when val < @floor, do: " "

  defp glyph(val) do
    n = tuple_size(@ramp)
    q = :math.sqrt(min(1, (val - @floor) / (@top - @floor)))
    elem(@ramp, min(n - 1, floor(q * n)))
  end
end
