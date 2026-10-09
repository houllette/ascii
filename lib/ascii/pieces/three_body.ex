defmodule Ascii.Pieces.ThreeBody do
  @moduledoc """
  Three equal masses sharing one figure-eight orbit.

  Three equal masses chasing each other round one figure eight, the periodic
  orbit of the three-body problem found by Moore and Simo.

  Ported from `src/pieces/three-body.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "three-body",
    category: :space,
    note: "three equal masses sharing one figure-eight orbit",
    cols: 65,
    rows: 15,
    fps: 30
  }

  # One lap in the orbit's own units of time.
  @period 6.32591398
  @steps 7200
  # Points kept along the path, evenly spaced in time.
  @n 720
  # Seconds per lap on screen.
  @lap 11
  # Points of tail behind each body.
  @trail 60

  @start_p [0.97000436, -0.24308753, -0.97000436, 0.24308753, 0, 0]
  @start_v [0.46620368, 0.43236573, 0.46620368, 0.43236573, -0.93240737, -0.86473146]
  @pairs for i <- [0, 2, 4], j <- [0, 2, 4], i != j, do: {i, j}

  @impl true
  def meta, do: @meta

  # Leapfrog over one lap, G = 1 and unit masses, keeping the first body's
  # path: a point every STEPS / N steps.
  defp integrate do
    dt = @period / @steps
    every = div(@steps, @n)
    p = List.to_tuple(@start_p)
    v = List.to_tuple(@start_v)

    {path, _} =
      Enum.map_reduce(0..(@n - 1), {p, v, acc(p)}, fn _, state ->
        {p, _, _} = state
        {{elem(p, 0), elem(p, 1)}, Enum.reduce(1..every, state, fn _, s -> step(s, dt) end)}
      end)

    path
  end

  defp step({p, v, a}, dt) do
    v = map6(v, a, fn vk, ak -> vk + ak * dt / 2 end)
    p = map6(p, v, fn pk, vk -> pk + vk * dt end)
    a = acc(p)
    {p, map6(v, a, fn vk, ak -> vk + ak * dt / 2 end), a}
  end

  defp map6({a0, a1, a2, a3, a4, a5}, {b0, b1, b2, b3, b4, b5}, f),
    do: {f.(a0, b0), f.(a1, b1), f.(a2, b2), f.(a3, b3), f.(a4, b4), f.(a5, b5)}

  defp acc(p) do
    Enum.reduce(@pairs, {0, 0, 0, 0, 0, 0}, fn {i, j}, a ->
      dx = elem(p, j) - elem(p, i)
      dy = elem(p, j + 1) - elem(p, i + 1)
      r2 = dx * dx + dy * dy
      r3 = r2 * :math.sqrt(r2)

      a
      |> put_elem(i, elem(a, i) + dx / r3)
      |> put_elem(i + 1, elem(a, i + 1) + dy / r3)
    end)
  end

  @impl true
  def init(_options) do
    %{cols: cols, rows: rows} = @meta
    path = integrate()
    x_max = Enum.reduce(path, 0, fn {x, _}, m -> max(m, abs(x)) end)
    y_max = Enum.reduce(path, 0, fn {_, y}, m -> max(m, abs(y)) end)

    # The eight spans the width less a margin; a cell is twice as tall as
    # wide. The height is rounded so each lobe's flat top sits mid-row.
    sx = (cols - 7) / (2 * x_max)
    sy = JSMath.round(y_max * sx * 0.5) / y_max

    # The orbit itself is a sparse dotted line, a dot about every two
    # columns, each taken from the point nearest its cell's centre and chosen
    # by how high in the cell the curve passes.
    {at, run} =
      Enum.map_reduce(path, [], fn {px, py}, run ->
        x = (cols - 1) / 2 + px * sx
        y = (rows - 1) / 2 - py * sy
        c = JSMath.round(x)
        r = JSMath.round(y)
        sub = y - r + 0.5
        dx = x - c
        dy = 2 * (sub - 0.5)
        off = dx * dx + dy * dy

        run =
          case run do
            [{^c, ^r, last_off, _} | rest] when off < last_off -> [{c, r, off, sub} | rest]
            [{^c, ^r, _, _} | _] -> run
            _ -> [{c, r, off, sub} | run]
          end

        {r * cols + c, run}
      end)

    {orbit, _, _} =
      run
      |> Enum.reverse()
      |> Enum.reduce({%{}, -9, -9}, fn {c, r, _, sub}, {orbit, lx, ly} ->
        if JSMath.hypot(c - lx, 2 * (r + sub - ly)) < 1.8 do
          {orbit, lx, ly}
        else
          {Map.put(orbit, r * cols + c, dot(sub)), c, r + sub}
        end
      end)

    %{at: List.to_tuple(at), orbit: orbit}
  end

  defp dot(sub) when sub < 0.36, do: "'"
  defp dot(sub) when sub < 0.64, do: "·"
  defp dot(_sub), do: "."

  defp cell(at, i), do: elem(at, rem(rem(i, @n) + @n, @n))

  @impl true
  def frame(%{at: at, orbit: orbit} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    head = JSMath.floor(JSMath.mod(t / @lap, 1) * @n)
    heads = for b <- 0..2, do: head + div(b * @n, 3)

    out =
      Enum.reduce(heads, orbit, fn h, out ->
        # A comet: one bright cell behind the head, then a run of : thinning
        # to a run of the faintest dot before it gives way to the orbit.
        {out, _, _} =
          Enum.reduce(1..@trail, {out, cell(at, h), 0}, fn i, {out, seen, k} ->
            q = cell(at, h - i)

            if q == seen do
              {out, seen, k}
            else
              k = k + 1

              ch =
                cond do
                  k <= 1 -> "o"
                  k <= 3 or i < @trail * 0.45 -> ":"
                  true -> "·"
                end

              {Map.put(out, q, ch), q, k}
            end
          end)

        out
      end)

    out = Enum.reduce(heads, out, &Map.put(&2, cell(at, &1), "O"))

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(out, r * cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
