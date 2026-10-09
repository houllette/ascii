defmodule Ascii.Pieces.Starlings do
  @moduledoc """
  A murmuration wheeling about, split by a passing falcon.

  A murmuration. Each bird matches its neighbours' heading, keeps to their
  middle and makes room for the one beside it, while a slow drift wheels the
  cloud about the middle. Every so often a falcon cuts through it.

  The simulation's state is threaded through `frame/3`: like upstream it
  runs fixed steps, at most twelve a frame, up to the step `t` asks for, and
  holds when `t` goes back. Upstream marks "no falcon" with `fx = NaN`, which
  makes every comparison with it false; here the falcon is `nil` then, and
  the flight from it and its drawing are skipped.

  Ported from `src/pieces/starlings.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}
  import Bitwise

  @meta %Ascii.Meta{
    name: "starlings",
    category: :creatures,
    note: "a murmuration wheeling about, split by a passing falcon",
    cols: 64,
    rows: 16,
    fps: 30
  }

  @cols 64
  @rows 16
  # A column and a row, in em.
  @cw 0.6
  @rh 1.2
  @n 320
  @dt 1 / 30
  # Steps before the first frame; between falcons; the step the first
  # falcon comes in on.
  @warm 200
  @pass 210
  @first @warm - 10
  # Neighbours are this close; this close is too close.
  @r 1.6
  @r2 1.6 * 1.6
  @sep2 0.85 * 0.85
  # How far ahead a bird looks for the edge; how hard it turns.
  @look 0.6
  @turn 90
  # Birds this close to the falcon scatter.
  @flee2 4.2 * 4.2

  @w @cols * @cw
  @h @rows * @rh
  # The open sky's oval, in from each side.
  @mx 1.5
  @my 1.2
  @gx Float.ceil(@w / @r) |> trunc()
  @gy Float.ceil(@h / @r) |> trunc()

  @ramp {" ", " ", ":", ";", "+", "*", "%", "%", "#", "#"}

  @impl true
  def meta, do: @meta

  # A smooth wave in [-1, 1] with period p.
  defp osc(t, p) do
    u = 1 - abs(2 * (t / p - JSMath.floor(t / p)) - 1)
    2 * u * u * (3 - 2 * u) - 1
  end

  @impl true
  def init(_options) do
    {birds, _} =
      Enum.map_reduce(1..@n, Int32.to_int32(26), fn _, r ->
        {a, r} = Int32.mulberry32(r)
        {b, r} = Int32.mulberry32(r)
        {c, r} = Int32.mulberry32(r)
        {d, r} = Int32.mulberry32(r)
        {{@w * (0.3 + 0.3 * a), @h * (0.3 + 0.4 * b), 6 + 2 * c, 2 * d - 1}, r}
      end)

    sim = %{
      k: 0,
      x: birds |> Enum.map(&elem(&1, 0)) |> List.to_tuple(),
      y: birds |> Enum.map(&elem(&1, 1)) |> List.to_tuple(),
      vx: birds |> Enum.map(&elem(&1, 2)) |> List.to_tuple(),
      vy: birds |> Enum.map(&elem(&1, 3)) |> List.to_tuple(),
      # The falcon: nil while none is hunting (upstream's NaN).
      fx: nil,
      fy: 0,
      fd: -1
    }

    steps(sim, @warm)
  end

  defp steps(sim, 0), do: sim
  defp steps(sim, n), do: sim |> step() |> steps(n - 1)

  @impl true
  def frame(sim, t, _env) do
    want = @warm + JSMath.floor(t / @dt + 1.0e-6)
    sim = catch_up(sim, want, 0)
    {draw(sim), nil, sim}
  end

  defp catch_up(%{k: k} = sim, want, s) when s < 12 and k < want,
    do: catch_up(step(sim), want, s + 1)

  defp catch_up(sim, _want, _s), do: sim

  defp step(%{k: k, x: x, y: y} = sim) do
    t = k * @dt
    ph = rem(k - @first + @pass * 9, @pass)
    hunting = k >= @first and ph < 90
    tx = @w * (0.5 + 0.12 * osc(t, 23))
    ty = @h * (0.5 + 0.1 * osc(t + 4, 11))
    cy = y |> Tuple.to_list() |> Enum.reduce(0, fn yi, cy -> cy + yi / @n end)

    # Each falcon comes in from the side the last one left by, level with
    # the flock, and bends toward the middle of it as it goes.
    {fd, fx, fy} =
      if hunting and ph == 0,
        do: {-sim.fd, if(sim.fd < 0, do: -2, else: @w + 2), cy},
        else: {sim.fd, sim.fx, sim.fy}

    {fx, fy} =
      if hunting,
        do: {fx + fd * 20 * @dt, fy + (cy - fy) * 3 * @dt},
        else: {nil, fy}

    cells = cells(x, y)
    falcon = if fx, do: {fx, fy}, else: nil

    {vx, vy} =
      Enum.reduce(0..(@n - 1), {sim.vx, sim.vy}, fn i, {vx, vy} ->
        {nvx, nvy} = bird(i, elem(x, i), elem(y, i), vx, vy, cells, tx, ty, falcon)
        {put_elem(vx, i, nvx), put_elem(vy, i, nvy)}
      end)

    x = for i <- 0..(@n - 1), do: elem(x, i) + elem(vx, i) * @dt
    y = for i <- 0..(@n - 1), do: elem(y, i) + elem(vy, i) * @dt

    %{
      sim
      | k: k + 1,
        x: List.to_tuple(x),
        y: List.to_tuple(y),
        vx: vx,
        vy: vy,
        fx: fx,
        fy: fy,
        fd: fd
    }
  end

  # The birds in each cell of the neighbour grid, as {j, x, y}, latest
  # first: upstream's head/next lists, walked in the same order.
  defp cells(x, y) do
    Enum.reduce(0..(@n - 1), %{}, fn i, cells ->
      xi = elem(x, i)
      yi = elem(y, i)

      c =
        min(@gy - 1, max(0, JSMath.floor(yi / @r))) * @gx +
          min(@gx - 1, max(0, JSMath.floor(xi / @r)))

      Map.update(cells, c, [{i, xi, yi}], &[{i, xi, yi} | &1])
    end)
  end

  defp bird(i, xi, yi, vx, vy, cells, tx, ty, falcon) do
    gx0 = JSMath.floor(xi / @r)
    gy0 = JSMath.floor(yi / @r)
    vxi = elem(vx, i)
    vyi = elem(vy, i)

    acc =
      for gy <- max(0, gy0 - 1)..min(@gy - 1, gy0 + 1)//1,
          gx <- max(0, gx0 - 1)..min(@gx - 1, gx0 + 1)//1,
          reduce: {0, 0, 0, 0, 0, 0, 0} do
        acc -> near(Map.get(cells, gy * @gx + gx, []), i, xi, yi, vx, vy, acc)
      end

    # Drift; align, cohere and separate.
    {ax, ay} = flock(acc, (tx - xi) * 0.25, (ty - yi) * 0.5, vxi, vyi)

    # A bird heading out of the open sky, an oval in the frame, turns back
    # toward the middle, harder the further out it is headed. It turns
    # rather than brakes, so the cloud wheels short of the edge.
    lx = (xi + vxi * @look - @w / 2) / (@w / 2 - @mx)
    ly = (yi + vyi * @look - @h / 2) / (@h / 2 - @my)
    out = JSMath.hypot(lx, ly) - 0.6
    {ax, ay} = if out > 0, do: turn(ax, ay, xi, yi, vxi, vyi, out), else: {ax, ay}

    # The falcon: birds near it break hard away and fly fast.
    {ax, ay, top} = flee(ax, ay, xi, yi, falcon)

    ux = vxi + ax * @dt
    uy = vyi + ay * @dt
    s = :math.sqrt(ux * ux + uy * uy)

    m =
      cond do
        s > top -> top / s
        s < 5 -> 5 / s
        true -> 1
      end

    {ux * m, uy * m}
  end

  defp flock({0, _, _, _, _, _, _}, ax, ay, _vxi, _vyi), do: {ax, ay}

  defp flock({n, sx, sy, svx, svy, px, py}, ax, ay, vxi, vyi) do
    {ax + ((svx / n - vxi) * 3 + sx / n * 0.5 + px * 4),
     ay + ((svy / n - vyi) * 3 + sy / n * 0.5 + py * 4)}
  end

  defp turn(ax, ay, xi, yi, vxi, vyi, out) do
    s = JSMath.hypot(vxi, vyi)
    side = if vxi * (@h / 2 - yi) - vyi * (@w / 2 - xi) > 0, do: 1, else: -1
    {ax + -vyi / s * side * @turn * out, ay + vxi / s * side * @turn * out}
  end

  defp flee(ax, ay, _xi, _yi, nil), do: {ax, ay, 10}

  defp flee(ax, ay, xi, yi, {fx, fy}) do
    dx = xi - fx
    dy = yi - fy
    d2 = dx * dx + dy * dy

    if d2 < @flee2,
      do: {ax + dx / (d2 + 0.4) * 90, ay + dy / (d2 + 0.4) * 90, 15},
      else: {ax, ay, 10}
  end

  # The neighbours in one cell, summed in upstream's order.
  defp near([], _i, _xi, _yi, _vx, _vy, acc), do: acc

  defp near([{i, _, _} | rest], i, xi, yi, vx, vy, acc), do: near(rest, i, xi, yi, vx, vy, acc)

  defp near([{j, xj, yj} | rest], i, xi, yi, vx, vy, {n, sx, sy, svx, svy, px, py} = acc) do
    dx = xj - xi
    dy = yj - yi
    d2 = dx * dx + dy * dy

    cond do
      d2 > @r2 ->
        near(rest, i, xi, yi, vx, vy, acc)

      d2 < @sep2 ->
        near(
          rest,
          i,
          xi,
          yi,
          vx,
          vy,
          {n + 1, sx + dx, sy + dy, svx + elem(vx, j), svy + elem(vy, j), px - dx / (d2 + 0.02),
           py - dy / (d2 + 0.02)}
        )

      true ->
        near(
          rest,
          i,
          xi,
          yi,
          vx,
          vy,
          {n + 1, sx + dx, sy + dy, svx + elem(vx, j), svy + elem(vy, j), px, py}
        )
    end
  end

  # Each character holds two places, one over the other: ' is a bird up
  # top, . one below, : two, and heavier marks as more crowd in.
  defp draw(%{x: x, y: y, k: k, fx: fx, fy: fy}) do
    counts =
      Enum.reduce(0..(@n - 1), %{}, fn i, counts ->
        c = JSMath.floor(elem(x, i) / @cw)
        r = JSMath.floor(elem(y, i) / @rh * 2)

        if c >= 0 and c < @cols and r >= 0 and r < @rows * 2 do
          key = (r >>> 1) * @cols + c
          {top, bot} = Map.get(counts, key, {0, 0})
          # Upstream counts in Uint8Arrays.
          bump = if (r &&& 1) == 1, do: {top, band(bot + 1, 255)}, else: {band(top + 1, 255), bot}
          Map.put(counts, key, bump)
        else
          counts
        end
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          case Map.get(counts, r * @cols + c, {0, 0}) do
            {1, 0} -> "'"
            {0, 1} -> "."
            {top, bot} -> elem(@ramp, min(tuple_size(@ramp) - 1, top + bot))
          end
        end
      end

    lines |> falcon(fx, fy, k) |> Enum.intersperse(?\n)
  end

  # The falcon, beating its wings as it goes.
  defp falcon(lines, nil, _fy, _k), do: lines

  defp falcon(lines, fx, fy, k) do
    fc = JSMath.round(fx / @cw)
    fr = JSMath.floor(fy / @rh)

    if fc > -2 and fc < @cols + 1 and fr >= 0 and fr < @rows do
      bird = if (k >>> 2 &&& 1) == 1, do: ["\\", "v", "/"], else: ["-", "v", "-"]

      List.update_at(lines, fr, fn row ->
        row = List.to_tuple(row)

        bird
        |> Enum.with_index(fc - 1)
        |> Enum.reduce(row, fn {ch, c}, row ->
          if c >= 0 and c < @cols, do: put_elem(row, c, ch), else: row
        end)
        |> Tuple.to_list()
      end)
    else
      lines
    end
  end
end
