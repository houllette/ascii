defmodule Ascii.Pieces.NewtonsCradle do
  @moduledoc """
  Five steel balls on strings passing one knock back and forth.

  Five chrome balls, each hung on a V of two strings from an A-frame. An end
  ball swings in and knocks; the far ball swings out and back.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with them.

    * `lifted` - how many balls swing in from each end, 1 to 4 (rounded): one
      knocks one out the far side, two knock two. Default 1.

  The picture is always 74 by 17. At the default it closes a loop every 8.2
  seconds, which a player draws once and repeats (see `Ascii.loop/1`).

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see `Ascii.Ink`),
  or on a page a CSS variable. On a light page, give it `paper: true`: its
  shading reads from the other end of its ramp, so dense characters still mean
  dark. It has no parts to colour one by one.

  ## Screen readers

  `Ascii.describe/1` gives its name and note, "newton's cradle: five steel
  balls on strings passing one knock back and forth". A player's or a
  component's `label` gives words of your own, as "a Newton's cradle".

  ## Example

  ```elixir
  anim = Ascii.new!("newtons-cradle", options: %{lifted: 2})
  {frame, _} = Ascii.frame(anim, 1.0)
  {frame.cols, frame.rows}
  #=> {74, 17}
  ```

  ```heex
  <Ascii.Phoenix.player socket={@socket} id="cradle" piece="newtons-cradle" options={%{lifted: 2}} />
  ```

  Ported from `src/pieces/newtons-cradle.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath

  @meta %Ascii.Meta{
    name: "newton's cradle",
    category: :physics,
    note: "five steel balls on strings passing one knock back and forth",
    cols: 74,
    rows: 17,
    fps: 30,
    options: %{lifted: 1},
    bounds: %{lifted: {1, 4}},
    loop: 8.2
  }

  @ramp {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}
  @n 5
  # Ball radius, in rows (a column is half a row); pivot to ball centre; the
  # pivots sit on this row line.
  @r 2
  @l 11
  @top 2
  # Seconds for one end to swing out and back, and for the knock to pass
  # through the row.
  @period 1.5
  @knock 0.07
  # Columns from a ball's pivot to each of its two string anchors.
  @span 3

  @cols 74
  @rows 17
  @cx @cols / 2
  # The row the base sits on.
  @base @top + @l + @r + 1
  # The top rail runs this many columns either side of centre; the legs step
  # out half a column a row.
  @rail 26
  @leg @rail + 0.5 + 0.5 * (@base - @top + 0.5)

  @compile {:inline, chrome: 5}

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{lifted: lifted}) do
    k = max(1, min(@n - 1, JSMath.round(lifted)))
    pivots = List.to_tuple(for i <- 0..(@n - 1), do: @cx + (i - (@n - 1) / 2) * 4 * @r)

    # The light is placed so a resting ball's highlight falls in one cell.
    m = JSMath.hypot(-0.67, 0.45, 0.59)
    light = {-0.67 / m, 0.45 / m, 0.59 / m}

    # The frame: a twin rail across the top on legs that splay out to a base.
    b0 = JSMath.floor(@cx - @leg) - 1
    b1 = JSMath.ceil(@cx + @leg)

    frame =
      Enum.map(JSMath.floor(@cx - @rail)..(JSMath.ceil(@cx + @rail) - 1), &{&1, @top - 1, "═"}) ++
        line(@cx - @rail - 0.5, @top - 0.5, @cx - @leg, @base) ++
        line(@cx + @rail + 0.5, @top - 0.5, @cx + @leg, @base) ++
        for c <- b0..b1 do
          {c, @base, if(c == b0, do: "▝", else: if(c == b1, do: "▘", else: "▀"))}
        end

    state = %{
      k: k,
      pivots: pivots,
      light: light,
      amp: 24 * :math.pi() / 180,
      frame: writes(frame)
    }

    # A ball hanging still, unpushed, is drawn the same every frame.
    resting =
      for paper <- [false, true], n <- 0..(@n - 1), into: %{} do
        {{n, paper}, hang(state, n, 0, 0, paper)}
      end

    Map.put(state, :resting, resting)
  end

  # The swing of the left group (negative) and right group (positive), and the
  # knock passing through the middle.
  defp pose(t, amp) do
    cyc = @period + 2 * @knock
    p = JSMath.mod(JSMath.mod(t, cyc) + cyc, cyc)
    w = 2 * :math.pi() / @period
    q = @period / 4

    cond do
      p < q -> {-amp * :math.cos(w * p), 0, 0}
      p < q + @knock -> {0, 0, :math.sin(:math.pi() * (p - q) / @knock)}
      p < 3 * q + @knock -> {0, amp * :math.sin(w * (p - q - @knock)), 0}
      p < 3 * q + 2 * @knock -> {0, 0, -:math.sin(:math.pi() * (p - 3 * q - @knock) / @knock)}
      true -> {-amp * :math.sin(w * (p - 3 * q - 2 * @knock)), 0, 0}
    end
  end

  # Cell writes {c, r, glyph}, floored, as indices into the frame, dropping
  # those outside it.
  defp writes(cells) do
    for {c, r, g} <- cells,
        c = JSMath.floor(c),
        r = JSMath.floor(r),
        c >= 0 and c < @cols and r >= 0 and r < @rows,
        do: {r * @cols + c, g}
  end

  # A line one glyph a row, or one a column where it runs flatter than a glyph.
  defp line(x0, y0, x1, y1) do
    s = (x1 - x0) / (y1 - y0)

    g =
      cond do
        abs(s) < 0.2 -> "|"
        s > 0 -> "\\"
        true -> "/"
      end

    if abs(s) <= 1 do
      for r <- JSMath.floor(y0)..(JSMath.ceil(y1 - 0.5) - 1)//1,
          r + 0.5 >= y0,
          do: {x0 + s * (r + 0.5 - y0), r, g}
    else
      {a, b} = if x0 < x1, do: {x0, x1}, else: {x1, x0}

      for c <- JSMath.floor(a)..(JSMath.ceil(b - 0.5) - 1)//1,
          c + 0.5 >= a,
          do: {c, y0 + (c + 0.5 - x0) / s, g}
    end
  end

  # Ball n's two strings and the ball, swung by th and nudged by push.
  defp hang(%{pivots: pivots, light: light}, n, th, push, paper) do
    sx = :math.sin(th)
    sy = :math.cos(th)
    pivot = elem(pivots, n)
    bx = pivot + push + 2 * @l * sx
    by = @top + @l * sy
    # Each string ties on just off the top of the ball.
    ax = pivot + push + 2 * (@l - @r) * sx
    ay = @top + (@l - @r) * sy

    writes(
      line(pivot - @span, @top, ax - 0.5 * sy, ay + 0.25 * sx) ++
        line(pivot + @span, @top, ax + 0.5 * sy, ay - 0.25 * sx)
    ) ++ writes(ball(bx, by, paper, light))
  end

  # How bright chrome is at a normal: the sky above, a dark horizon band, the
  # base below, and a hard highlight. Below 0.014 the highlight's tenth power
  # is too small to move a sum that is at least 0.03, so it is left out there.
  defp chrome(ny, nz, nxl, nyl, lz) do
    # Where the view reflects to, up or down.
    ry = 2 * nz * ny

    env =
      cond do
        ry > 0.15 -> 0.3 + 0.25 * ry
        ry > -0.5 -> 0.03
        true -> 0.5 - 0.2 * (ry + 0.5)
      end

    dot = nxl + nyl + nz * lz
    base = 2 * nz * dot - lz
    spec = if base > 0.014, do: :math.pow(base, 10), else: 0
    min(1, env + 0.12 * max(0, dot) + 3.5 * spec)
  end

  # A ball sampled 4x4 per cell, so it moves smoothly between cells and keeps
  # a round rim.
  defp ball(bx, by, paper, {lx, ly, lz}) do
    cols =
      for c <- JSMath.floor(bx - 2 * @r)..(JSMath.ceil(bx + 2 * @r) - 1)//1 do
        {c,
         for i <- 0..3 do
           nx = (c + 0.125 + i * 0.25 - bx) / 2 / @r
           {nx * nx, nx * lx}
         end}
      end

    runs =
      for r <- JSMath.floor(by - @r)..(JSMath.ceil(by + @r) - 1)//1 do
        ys =
          for j <- 0..3 do
            ny = -(r + 0.125 + j * 0.25 - by) / @r
            {j, ny, ny * ny, ny * ly}
          end

        for {c, xs} <- cols, cell = cell(xs, ys, lz, paper), cell != nil, do: {c, r, cell}
      end

    # A sliver of rim on the very top or bottom, under a full row, reads as a
    # nub: leave it off.
    runs
    |> trim_nub()
    |> Enum.reverse()
    |> trim_nub()
    |> Enum.reverse()
    |> Enum.concat()
  end

  defp trim_nub([first, second | rest]) when length(first) < 3 and length(second) > 5,
    do: [[], second | rest]

  defp trim_nub(runs), do: runs

  defp cell(xs, ys, lz, paper) do
    {hit, v, cy} =
      Enum.reduce(ys, {0, 0, 0}, fn {j, ny, ny2, nyl}, acc ->
        Enum.reduce(xs, acc, fn {nx2, nxl}, {hit, v, cy} = acc ->
          q = nx2 + ny2

          if q >= 1,
            do: acc,
            else: {hit + 1, v + chrome(ny, :math.sqrt(1 - q), nxl, nyl, lz), cy + j}
        end)
      end)

    cond do
      hit < 4 -> nil
      hit < 6 -> rim(cy / hit)
      true -> shade(v, hit, paper)
    end
  end

  defp rim(cy) when cy < 1.5, do: "'"
  defp rim(cy) when cy > 2, do: "."
  defp rim(_cy), do: "-"

  defp shade(v, hit, paper) do
    g = max(1, JSMath.round(v / hit * (tuple_size(@ramp) - 1)))
    elem(@ramp, if(paper, do: tuple_size(@ramp) - g, else: g))
  end

  @impl true
  def frame(%{k: k, resting: resting} = state, t, %{paper: paper}) do
    {left, right, knock} = pose(t, state.amp)

    out =
      Enum.reduce(0..(@n - 1), Map.new(state.frame), fn n, out ->
        # Only one end swings at a time, so a ball in both end groups (four
        # lifted) takes whichever is moving.
        th = if(n < k, do: left, else: 0) + if(n >= @n - k, do: right, else: 0)

        # A knock nudges the row a fraction of a column toward the ball about
        # to leave, which waits for it.
        push =
          if (knock > 0 and n < @n - k) or (knock < 0 and n >= k), do: 0.5 * knock, else: 0

        cells =
          if th == 0 and push == 0,
            do: Map.fetch!(resting, {n, paper}),
            else: hang(state, n, th, push, paper)

        Enum.reduce(cells, out, fn {i, g}, out -> Map.put(out, i, g) end)
      end)

    lines =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1), do: Map.get(out, r * @cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
