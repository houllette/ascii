defmodule Ascii.Pieces.GlxgearsTest.Upstream do
  @moduledoc false
  # A plain port of upstream's glxgears.ts, line for line: every point is
  # plotted in upstream's order, with Math.sin and Math.cos of its angle,
  # into a Float32 depth buffer (a map here). No fast paths, no margins.

  alias Ascii.JSMath

  @cols 56
  @rows 31
  @w @cols * 2
  @h @rows * 2
  @tau :math.pi() * 2
  @rad :math.pi() / 180
  # Columns per unit, the spacing of sampled points in units, and degrees a
  # second for the big gear.
  @scale 4.2
  @ds 0.05
  @speed 17
  @shade {" ", "░", "▒", "▓", "█"}
  # Tooth depth; gears.c has 0.7.
  @depth 0.8

  def init(_options) do
    # glRotatef(view_rotx = 20) then glRotatef(view_roty = 30); light at (5, 5, 10).
    view = %{
      cy: :math.cos(30 * @rad),
      sy: :math.sin(30 * @rad),
      cx: :math.cos(20 * @rad),
      sx: :math.sin(20 * @rad)
    }

    m = JSMath.hypot(5, 5, 10)
    light = {5 / m, 5 / m, 10 / m}
    gears = gears()
    {left, high} = frame_origin(gears, view)

    %{view: view, light: light, gears: gears, left: left, high: high}
  end

  # gear(inner, outer, width, teeth), its place, its turn as k * a + off, and
  # its face's shade. Twelve and six teeth for twenty and ten, so each tooth is
  # wide enough to read.
  defp gears do
    raw = [
      %{r0: 1.0, r: 4.0, w: 1.0, n: 12, x: -3.0, y: -2.0, k: 1, off: 0, face: 3},
      %{r0: 0.5, r: 2.0, w: 2.0, n: 6, x: 3.1, y: -2.0, k: -2, off: nil, face: 2},
      %{r0: 1.3, r: 2.0, w: 0.5, n: 6, x: -3.1, y: 4.2, k: -2, off: nil, face: 2}
    ]

    big = hd(raw)

    # Offsets that set each small gear's gap on a tooth of the big one.
    Enum.map(raw, fn g ->
      g = %{g | r: g.r} |> Map.merge(%{r1: g.r - @depth / 2, r2: g.r + @depth / 2})

      if g.k == 1 do
        g
      else
        dir = :math.atan2(g.y - big.y, g.x - big.x)
        off = (dir + :math.pi() - (0.875 - dir * big.n / @tau + 0.375) * @tau / g.n) / @rad
        %{g | off: off}
      end
    end)
  end

  defp across(x, z, v), do: x * v.cy + z * v.sy
  defp up(x, y, z, v), do: y * v.cx + (x * v.sy - z * v.cy) * v.sx

  # Centre the gears' outer circles in the frame.
  defp frame_origin(gears, v) do
    {left, right, high, low} =
      Enum.reduce(gears, {nil, nil, nil, nil}, fn g, acc ->
        g
        |> angles(0.0, 0.02)
        |> Enum.reduce(acc, fn th, acc ->
          Enum.reduce([-g.w / 2, g.w / 2], acc, fn z, {l, r, hi, lo} ->
            x = g.x + g.r2 * :math.cos(th)
            y = g.y + g.r2 * :math.sin(th)
            a = across(x, z, v)
            u = up(x, y, z, v)
            {min_of(l, a), max_of(r, a), max_of(hi, u), min_of(lo, u)}
          end)
        end)
      end)

    {left - (@cols / @scale - (right - left)) / 2, high + (2 * @rows / @scale - (high - low)) / 2}
  end

  defp min_of(nil, b), do: b
  defp min_of(a, b), do: min(a, b)
  defp max_of(nil, b), do: b
  defp max_of(a, b), do: max(a, b)

  defp angles(_g, from, step),
    do: from |> Stream.iterate(&(&1 + step)) |> Enum.take_while(&(&1 < @tau))

  # The tooth outline as radius by angle: up a flank, across, down, the root.
  defp radius(g, th) do
    u = th * g.n / @tau - floor(th * g.n / @tau)

    rise =
      cond do
        u < 0.25 -> u * 4
        u < 0.5 -> 1
        u < 0.75 -> (0.75 - u) * 4
        true -> 0
      end

    g.r1 + (g.r2 - g.r1) * rise
  end

  def frame(state, t, env) do
    a = @speed * t

    zbuf =
      state.gears
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {g, i}, zbuf ->
        spin = (g.k * a + g.off) * @rad
        h = g.w / 2
        plot = fn zb, x, y, z, nx, ny, face -> plot(zb, state, g, i, x, y, z, nx, ny, face) end

        # The front face, ring by ring. The back face never turns to the eye.
        zbuf =
          @ds
          |> rings(g)
          |> Enum.reduce(zbuf, fn r, zb ->
            Enum.reduce(ring(r), zb, fn th, zb ->
              if r <= radius(g, th) do
                plot.(
                  zb,
                  g.x + r * :math.cos(th + spin),
                  g.y + r * :math.sin(th + spin),
                  h,
                  0,
                  0,
                  true
                )
              else
                zb
              end
            end)
          end)

        zs = zs(h)

        # The outer wall, walked by arc length so the flanks are as dense as the tips.
        zbuf =
          Enum.reduce(wall(g), zbuf, fn {th, r, dr, l}, zb ->
            c = :math.cos(th + spin)
            s = :math.sin(th + spin)

            Enum.reduce(zs, zb, fn z, zb ->
              plot.(
                zb,
                g.x + r * c,
                g.y + r * s,
                z,
                (r * c + dr * s) / l,
                (r * s - dr * c) / l,
                false
              )
            end)
          end)

        # The bore, facing in.
        g
        |> angles(0.0, @ds / g.r0)
        |> Enum.reduce(zbuf, fn th, zb ->
          c = :math.cos(th)
          s = :math.sin(th)

          Enum.reduce(zs, zb, fn z, zb ->
            plot.(zb, g.x + g.r0 * c, g.y + g.r0 * s, z, -c, -s, false)
          end)
        end)
      end)

    {Enum.intersperse(cells(zbuf, env.paper), ?\n), nil, state}
  end

  defp rings(ds, g), do: g.r0 |> Stream.iterate(&(&1 + ds)) |> Enum.take_while(&(&1 < g.r2))
  defp ring(r), do: 0 |> Stream.iterate(&(&1 + @ds / r)) |> Enum.take_while(&(&1 < @tau))

  defp zs(h), do: -h |> Stream.iterate(&(&1 + @ds)) |> Enum.take_while(&(&1 <= h))

  defp wall(g), do: wall(g, 0, [])

  defp wall(_g, th, acc) when th >= @tau, do: Enum.reverse(acc)

  defp wall(g, th, acc) do
    r = radius(g, th)
    dr = (radius(g, th + 1.0e-4) - radius(g, th - 1.0e-4)) / 2.0e-4
    l = JSMath.hypot(r, dr)
    wall(g, th + @ds / l, [{th, r, dr, l} | acc])
  end

  # A point and its normal in gear space; a wall's normal has no z.
  defp plot(zb, state, g, i, x, y, z, nx, ny, face) do
    v = state.view
    col = floor((across(x, z, v) - state.left) * @scale * 2)
    row = floor((state.high - up(x, y, z, v)) * @scale)

    if col < 0 or col >= @w or row < 0 or row >= @h do
      zb
    else
      k = row * @w + col
      d = y * v.sx + (z * v.cy - x * v.sy) * v.cx

      case zb do
        %{^k => {d0, _, _}} when d <= d0 ->
          zb

        _ ->
          vx = nx * v.cy
          vy = ny * v.cx + nx * v.sy * v.sx
          vz = ny * v.sx - nx * v.sy * v.cx

          if not face and vz < 0 do
            zb
          else
            {l0, l1, l2} = state.light
            # A wall is full where it faces the light, and faint where it does not.
            tone =
              cond do
                face -> g.face
                vx * l0 + vy * l1 + vz * l2 > 0.42 -> 4
                true -> 1
              end

            Map.put(zb, k, {JSMath.fround(d), i, tone})
          end
      end
    end
  end

  # A cell shows the shade that covers most of its four samples, the nearer
  # on a tie, and nothing if fewer than two are covered.
  defp cells(zbuf, paper) do
    for row <- 0..(@rows - 1) do
      for col <- 0..(@cols - 1), do: cell(zbuf, row, col, paper)
    end
  end

  defp cell(zbuf, row, col, paper) do
    ks = [
      2 * row * @w + 2 * col,
      2 * row * @w + 2 * col + 1,
      (2 * row + 1) * @w + 2 * col,
      (2 * row + 1) * @w + 2 * col + 1
    ]

    case Enum.reduce(ks, {0, nil, %{}}, &vote(zbuf, &1, &2)) do
      {covered, best, _} when covered >= 2 ->
        v = rem(best, 5)
        elem(@shade, if(paper, do: 5 - v, else: v))

      _ ->
        " "
    end
  end

  defp vote(zbuf, k, {covered, best, seen} = acc) do
    case zbuf do
      %{^k => {d, who, tone}} ->
        c = who * 5 + tone
        seen = Map.update(seen, c, {1, d}, fn {n, near} -> {n + 1, max(near, d)} end)
        {cn, cnear} = seen[c]
        {bn, bnear} = if best == nil, do: {0, 0}, else: seen[best]
        best = if best == nil or cn > bn or (cn == bn and cnear > bnear), do: c, else: best
        {covered + 1, best, seen}

      _ ->
        acc
    end
  end
end

defmodule Ascii.Pieces.GlxgearsTest do
  use ExUnit.Case, async: true
  use Ascii.ContractCase, piece: Ascii.Pieces.Glxgears
  use Ascii.GoldenCase, slug: "glxgears", piece: Ascii.Pieces.Glxgears

  alias Ascii.Pieces.Glxgears
  alias Ascii.Pieces.GlxgearsTest.Upstream

  # The port keeps a quantised depth per sample and settles near ties
  # exactly, places face points by rotation with an exact fallback near
  # sample edges, and redoes a cell's vote exactly when depths are close.
  # Upstream below, plainly, decides all of that.

  setup_all do
    %{piece: Glxgears.init(Glxgears.meta().options), upstream: Upstream.init(%{})}
  end

  property "frames match a plain port of upstream at random times", context do
    check all(
            times <- list_of(float(min: 0.0, max: 120.0), min_length: 1, max_length: 3),
            paper <- boolean(),
            max_runs: 50
          ) do
      assert_same(context, times, paper)
    end
  end

  # At 136/24 s points of different shades reach one sample at the same
  # quantised depth, and upstream's Float32Array rule (the first to reach
  # the rounded depth, unless a later one lies above it) picks a different
  # one from the largest key: the exact settling is what gets this right.
  test "a depth tie between shades in one sample goes upstream's way", context do
    assert_same(context, [136 / 24], false)
  end

  defp assert_same(%{piece: piece, upstream: upstream}, times, paper) do
    ours = play(Glxgears, piece, times, paper)
    theirs = play(Upstream, upstream, times, paper)

    for {t, a, b} <- Enum.zip([times, ours, theirs]) do
      assert a == b, "t = #{t}, paper: #{paper}\n\nport:\n#{a}\n\nupstream:\n#{b}"
    end
  end

  # Each a fresh instance, threading its state through the times in turn.
  defp play(mod, state, times, paper) do
    env = %Ascii.Env{cols: 56, rows: 31, paper: paper}

    {frames, _} =
      Enum.map_reduce(times, state, fn t, state ->
        {io, nil, state} = mod.frame(state, t * 1.0, env)
        {IO.iodata_to_binary(io), state}
      end)

    frames
  end
end
