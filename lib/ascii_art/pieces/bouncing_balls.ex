defmodule AsciiArt.Pieces.BouncingBalls do
  @moduledoc """
  Rubber balls bouncing lower each time, squashing on landing.

  Rubber balls dropping onto a floor and knocking into each other, squashing
  on every landing; a ball that comes to rest crouches and leaps.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `balls` - how many, 1 to 5 (rounded), each its own size and bounce,
      spread across the floor and taking turns to leap. Default 3.

  The picture is always 64 by 22.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `AsciiArt.Ink`),
  or on a page a CSS variable. On a light page, give it `paper: true`: its
  shading reads from the other end of its ramp, so dense characters still mean
  dark. It has no parts to colour one by one.

  ## Screen readers

  `AsciiArt.describe/1` gives its name and note, "bouncing balls: rubber balls
  bouncing lower each time, squashing on landing". A player's or a component's
  `label` gives words of your own, as "balls bouncing".

  ## Example

  ```elixir
  anim = AsciiArt.new!("bouncing-balls", options: %{balls: 5}, ink: "#ff7a59")
  {frame, _} = AsciiArt.frame(anim, 1.5)
  {frame.cols, frame.rows, frame.palette}
  #=> {64, 22, ["#ff7a59"]}
  ```

  ```heex
  <AsciiArt.Phoenix.player socket={@socket} id="balls" piece="bouncing-balls" options={%{balls: 1}} />
  ```

  Ported from `src/pieces/bouncing-balls.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}

  @meta %AsciiArt.Meta{
    name: "bouncing balls",
    category: :physics,
    note: "rubber balls bouncing lower each time, squashing on landing",
    cols: 64,
    rows: 22,
    fps: 30,
    options: %{balls: 3},
    bounds: %{balls: {1, 5}}
  }

  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  # Gravity, rows per second squared; the physics step; contact stiffness: a
  # ball of radius r rings at @stiff / r.
  @g 80
  @h 1 / 900
  @stiff 120
  # Radii, in rows (a column is half a row), and how much of each landing
  # each ball keeps.
  @sizes {3.0, 2.3, 1.7, 2.6, 2.0}
  @bounce {0.84, 0.82, 0.8, 0.83, 0.81}
  # Seconds between the balls' first leaps; seconds played before the first frame.
  @spread 2.1
  @warm 9.1
  # A shadow's glyphs, from a ball on the floor to one high above it.
  @shadow {"▀", "▒", "░"}

  @cols 64
  @rows 22
  # The floor's width, in rows; the floor line sits on the top edge of row @floor.
  @w @cols / 2
  @floor @rows - 1

  # sqrt(hit / 16) for each count of subsamples inside the ball.
  @coverage List.to_tuple(for hit <- 0..16, do: :math.sqrt(hit / 16))

  @compile {:inline, shade: 8}

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{balls: balls}) do
    m = JSMath.hypot(-0.45, 0.55, 0.7)
    {lx, ly, lz} = {-0.45 / m, 0.55 / m, 0.7 / m}
    hm = JSMath.hypot(lx, ly, lz + 1)
    # Halfway between the light and the eye.
    {hx, hy, hz} = {lx / hm, ly / hm, (lz + 1) / hm}
    n = max(1, min(tuple_size(@sizes), JSMath.round(balls)))

    bs =
      for i <- 0..(n - 1) do
        r = elem(@sizes, i)
        w = @stiff / r
        e = elem(@bounce, i)
        z = -:math.log(e) / JSMath.hypot(:math.pi(), :math.log(e))
        x = @w * (0.2 + 0.6 * i / max(1, n - 1))

        # They start resting on the floor and take turns to leap, so they never
        # move in step.
        %{
          r: r,
          k: w * w,
          c: 2 * z * w,
          x: x,
          y: r,
          vx: 0,
          vy: 0,
          rest: 0,
          crouch: -@spread * i,
          sq: 0
        }
      end

    sim = %{bs: List.to_tuple(bs), n: n, rand: Int32.to_int32(11)}
    warm_steps = JSMath.round(1 / 30 / @h)

    sim =
      Enum.reduce(1..JSMath.ceil(@warm * 30)//1, sim, fn _, sim -> advance(sim, warm_steps) end)

    %{sim: sim, last: 0, light: {lx, ly, lz, hx, hy, hz}}
  end

  defp advance(sim, steps), do: Enum.reduce(1..steps//1, sim, fn _, sim -> step(sim) end)

  defp step(%{bs: bs, n: n, rand: rand} = sim) do
    {bs, rand} =
      Enum.reduce(0..(n - 1), {bs, rand}, fn i, {bs, rand} ->
        {b, rand} = move(elem(bs, i), rand)
        {put_elem(bs, i, b), rand}
      end)

    # Balls that touch trade momentum along the line between their centres.
    bs =
      for i <- 0..(n - 1), j <- (i + 1)..(n - 1)//1, reduce: bs do
        bs -> collide(bs, i, j)
      end

    %{sim | bs: bs, rand: rand}
  end

  # Settled: crouch into the floor for a moment, then spring up.
  defp move(%{crouch: crouch, r: r} = b, rand) when crouch != nil do
    crouch = crouch + @h
    u = max(0, min(1, crouch / 0.45))
    sq = 0.3 * r * u * u * (3 - 2 * u)
    b = %{b | crouch: crouch, sq: sq, y: r - sq, vx: b.vx * (1 - 6 * @h)}
    if u >= 1, do: launch(b, rand), else: {b, rand}
  end

  defp move(%{r: r, x: x, y: y} = b, rand) do
    vy = b.vy - @g * @h
    d = r - y

    {vy, vx, rest, crouch} =
      if d > 0 do
        vy = vy + max(0, b.k * d - b.c * vy) * @h
        rest = b.rest + @h
        {vy, b.vx * (1 - 0.8 * @h), rest, if(rest > 0.3, do: 0, else: nil)}
      else
        {vy, b.vx, 0, nil}
      end

    # A knock from below never sends a ball out of the top of the frame.
    vy = min(vy, :math.sqrt(2 * @g * max(0, @floor - 1.2 - r - y)))
    x = x + vx * @h
    y = y + vy * @h
    {x, vx} = if x < r, do: {r, abs(vx) * 0.85}, else: {x, vx}
    {x, vx} = if x > @w - r, do: {@w - r, -abs(vx) * 0.85}, else: {x, vx}

    {%{b | vy: vy, vx: vx, rest: rest, crouch: crouch, sq: max(0, d), x: x, y: y}, rand}
  end

  defp launch(b, rand) do
    # High enough to fill the frame, never so high the ball leaves it.
    {a, rand} = Int32.mulberry32(rand)
    vy = :math.sqrt(2 * @g * (@floor - 1.5 - 2 * b.r) * (0.75 + 0.25 * a))
    {a, rand} = Int32.mulberry32(rand)
    vx = (@w / 2 - b.x) * 0.3 + (a - 0.5) * 10
    # Spring straight back to round.
    {%{b | vy: vy, vx: vx, y: b.r, crouch: nil, rest: 0}, rand}
  end

  defp collide(bs, i, j) do
    a = elem(bs, i)
    b = elem(bs, j)
    dx = b.x - a.x
    dy = b.y - a.y
    dist = JSMath.hypot(dx, dy)
    gap = a.r + b.r - dist

    if gap <= 0 or dist == 0 do
      bs
    else
      nx = dx / dist
      ny = dy / dist
      ma = a.r * a.r
      mb = b.r * b.r
      vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny

      {a, b} =
        if vn < 0 do
          jm = -1.85 * vn / (1 / ma + 1 / mb)

          {%{a | vx: a.vx - jm * nx / ma, vy: a.vy - jm * ny / ma},
           %{b | vx: b.vx + jm * nx / mb, vy: b.vy + jm * ny / mb}}
        else
          {a, b}
        end

      pa = mb / (ma + mb)
      pb = ma / (ma + mb)

      a = %{
        a
        | x: a.x - nx * gap * pa,
          y: a.y - ny * gap * pa,
          crouch: if(a.crouch != nil and ny < 0, do: nil, else: a.crouch)
      }

      b = %{
        b
        | x: b.x + nx * gap * pb,
          y: b.y + ny * gap * pb,
          crouch: if(b.crouch != nil and ny > 0, do: nil, else: b.crouch)
      }

      bs |> put_elem(i, a) |> put_elem(j, b)
    end
  end

  @impl true
  def frame(%{sim: sim, last: last, light: light} = state, t, %{paper: paper}) do
    dt = min(0.1, max(0, t - last))
    sim = advance(sim, JSMath.round(dt / @h))
    balls = Tuple.to_list(sim.bs)

    out = Enum.reduce(balls, %{}, &shadow/2)

    # Smaller balls are nearer, so they draw last.
    out =
      balls
      |> Enum.sort_by(& &1.r, :desc)
      |> Enum.reduce(out, &draw(&1, &2, paper, light))

    lines =
      for r <- 0..(@rows - 1) do
        blank = if r == @floor, do: "▔", else: " "
        for c <- 0..(@cols - 1), do: Map.get(out, r * @cols + c, blank)
      end

    {Enum.intersperse(lines, ?\n), nil, %{state | sim: sim, last: t}}
  end

  # The shadow narrows and pales as the ball rises.
  defp shadow(%{r: r, x: x, y: y, sq: sq}, out) do
    h = max(0, y - r) / (@floor - 2 * r)
    rx = r * r / (r - sq)
    sw = rx * 2 * (1 - 0.6 * h)
    x2 = x * 2

    Enum.reduce(JSMath.ceil(x2 - sw)..(JSMath.ceil(x2 + sw) - 1)//1, out, fn c, out ->
      edge = abs(c + 0.5 - x2) / sw
      g = min(tuple_size(@shadow) - 1, JSMath.floor(h * 2.6 + edge * 1.3))

      if c >= 0 and c < @cols,
        do: Map.put(out, @floor * @cols + c, elem(@shadow, g)),
        else: out
    end)
  end

  defp draw(%{r: r, x: x, y: y, sq: sq}, out, paper, light) do
    # A squashed ball keeps its area: shorter by what it has sunk, wider to match.
    ry = r - sq
    rx = r * r / ry
    cy = @floor - ry - max(0, y - r)
    cx = x * 2
    {lx, ly, lz, hx, hy, hz} = light

    c_lo = max(JSMath.floor(cx - 2 * rx), 0)
    c_hi = min(JSMath.floor(cx + 2 * rx), @cols - 1)

    # Per column, the four subsample offsets across, and their products with
    # the light and the highlight.
    columns =
      for c <- c_lo..c_hi//1 do
        us =
          for i <- 0..3 do
            u = (c + 0.125 + i * 0.25 - cx) / 2 / rx
            {u * u, u * lx, u * hx}
          end

        {c, us}
      end

    runs =
      for row <- JSMath.floor(cy - ry)..JSMath.floor(cy + ry)//1 do
        if row < 0 or row >= @floor do
          []
        else
          ws =
            for j <- 0..3 do
              w = (row + 0.125 + j * 0.25 - cy) / ry
              {w * w, -w * ly, -w * hy, 0.12 * max(0, w)}
            end

          run(row, columns, ws, paper, {lz, hz})
        end
      end

    # A sliver of a row on the very top or bottom, over a much wider one,
    # reads as a nub: leave it off.
    runs
    |> trim_nub()
    |> Enum.reverse()
    |> trim_nub()
    |> Enum.reduce(out, fn run, out ->
      Enum.reduce(run, out, fn {k, g}, out -> Map.put(out, k, g) end)
    end)
  end

  defp trim_nub([first, second, _ | _] = runs) when length(first) < 3 and length(second) > 5,
    do: [[] | tl(runs)]

  defp trim_nub(runs), do: runs

  defp run(row, columns, ws, paper, {lz, hz}) do
    for {c, us} <- columns, g = cell(us, ws, paper, lz, hz), g > 0 do
      {row * @cols + c, elem(@ramp, g)}
    end
  end

  defp cell(us, ws, paper, lz, hz) do
    {hit, v} =
      Enum.reduce(ws, {0, 0}, fn {ww, wly, why, under}, acc ->
        Enum.reduce(us, acc, fn {uu, ulx, uhx}, {hit, v} = acc ->
          q = uu + ww

          if q < 1,
            do: {hit + 1, v + shade(ulx, uhx, wly, why, under, :math.sqrt(1 - q), lz, hz)},
            else: acc
        end)
      end)

    if hit < 4 do
      0
    else
      # A cell the rim only clips gets a lighter glyph, so the edge is smooth
      # rather than outlined.
      ink = if paper, do: 1.1 - v / hit, else: v / hit
      JSMath.round(min(1, ink) * elem(@coverage, hit) * (tuple_size(@ramp) - 1))
    end
  end

  # How bright rubber is at a normal: soft light from the upper left, a small
  # highlight set in from the rim, and the floor lighting the underside a little.
  # Below 0.35 the highlight's 40th power is under 1e-18, too small to move a
  # sum that is at least 0.14, so it is left out there.
  defp shade(ulx, uhx, wly, why, under, nz, lz, hz) do
    d = max(0, ulx + wly + nz * lz)
    s = uhx + why + nz * hz
    s = if s > 0.35, do: :math.pow(s, 40), else: 0
    min(1, 0.14 + 0.66 * d + 0.5 * s + under)
  end
end
