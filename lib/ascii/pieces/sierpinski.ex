defmodule Ascii.Pieces.Sierpinski do
  @moduledoc """
  The chaos game filling a sierpinski triangle point by point.

  The chaos game. A point jumps halfway to a corner picked at random, over
  and over, and every spot it lands on stays lit.

  Ported from `src/pieces/sierpinski.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath}
  import Bitwise

  @meta %Ascii.Meta{
    name: "sierpinski",
    category: :generative,
    note: "the chaos game filling a sierpinski triangle point by point",
    cols: 59,
    rows: 26,
    fps: 20
  }

  # A cell's quarters: 1 2 above, 4 8 below.
  @quad {" ", "▘", "▝", "▀", "▖", "▌", "▞", "▛", "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█"}
  # Seconds from one empty frame to the next.
  @cycle 9.6
  # Seconds of plotting, slow at first and then a flood.
  @fill 6
  # The finished triangle stays until here, and has been erased along one
  # unbroken path by @clear.
  @hold 7.3
  @clear 9.3
  # Play opens on the finished triangle.
  @start 6.1
  @points 12_000
  # How fast the plotting speeds up.
  @rate 1
  # Throws a second underneath the flood.
  @steady 60
  # Levels of the figure a quarter is tested against.
  @depth 7

  # Quarter cells: half a column wide, half a row tall.
  @w 59 * 2
  @h 26 * 2
  # A quarter cell is twice as tall as it is wide, so an equilateral triangle
  # of height h quarters is h / sin 60 columns across.
  @top 2
  @base @h - 2

  @impl true
  def meta, do: @meta

  @impl true
  def init(_options) do
    %{cols: cols} = @meta
    half = (@base - @top) / :math.sin(:math.pi() / 3)
    corners = {{cols, @top}, {cols - half, @base}, {cols + half, @base}}

    # A quarter belongs to the figure when two of its 16 sample points do;
    # its rank is the earliest of their places along the path.
    rank =
      for qy <- 0..(@h - 1), qx <- 0..(@w - 1) do
        {n, first} =
          Enum.reduce(0..15, {0, 2}, fn i, {n, first} ->
            at = place(qx + (band(i, 3) + 0.5) / 4, qy + (bsr(i, 2) + 0.5) / 4, half)
            if at >= 0, do: {n + 1, min(first, at)}, else: {n, first}
          end)

        if n >= 2, do: JSMath.fround(first), else: -1
      end
      |> List.to_tuple()

    # The cell each corner's own quarter falls in, nudged inside the triangle.
    marks =
      [{0, 1}, {1, -1}, {-1, -1}]
      |> Enum.with_index()
      |> Enum.map(fn {{dx, dy}, i} ->
        {x, y} = elem(corners, i)
        floor((x + dx) / 2) + floor((y + dy) / 2) * cols
      end)
      |> MapSet.new()

    %{
      rank: rank,
      corners: corners,
      marks: marks,
      scale: (@points - @steady * @fill) / (:math.exp(@rate * @fill) - 1),
      cycle: -1,
      first: %{}
    }
  end

  # Where a point sits in the figure: -1 in a hole, else its place along the
  # arrowhead path that runs from the left corner over the apex to the right,
  # visiting every sub-triangle in turn. Corners are 0 apex, 1 left, 2 right.
  defp place(x, y, half) do
    v = (y - @top) / (@base - @top)
    s = (x - @meta.cols) / half
    w = {1 - v, (v - s) / 2, (v + s) / 2}

    if elem(w, 0) < 0 or elem(w, 1) < 0 or elem(w, 2) < 0,
      do: -1,
      else: descend(w, {1, 0, 2}, 0, 1, @depth)
  end

  defp descend(_w, _p, at, _step, 0), do: at

  defp descend({w0, w1, w2}, {p0, p1, p2} = p, at, step, levels) do
    k =
      cond do
        w0 >= 0.5 -> 0
        w1 >= 0.5 -> 1
        w2 >= 0.5 -> 2
        true -> nil
      end

    if k == nil do
      -1
    else
      w = {grow(w0, k == 0), grow(w1, k == 1), grow(w2, k == 2)}

      i =
        cond do
          p0 == k -> 0
          p1 == k -> 1
          true -> 2
        end

      step = step / 3

      p =
        case i do
          0 -> {p0, p2, p1}
          2 -> {p1, p0, p2}
          1 -> p
        end

      descend(w, p, at + i * step, step, levels - 1)
    end
  end

  defp grow(w, true), do: 2 * w - 1
  defp grow(w, false), do: 2 * w

  # The throw that first lit each quarter, for the k-th game; anything the
  # game misses lights on the last throw.
  defp build(corners, k) do
    {r, rand} = Int32.mulberry32(Int32.to_int32(k * 977 + 31))
    {x, y} = elem(corners, Int32.to_int32(r * 3))

    {first, _, _, _} =
      Enum.reduce(0..(@points - 1), {%{}, x, y, rand}, fn n, {first, x, y, rand} ->
        {r, rand} = Int32.mulberry32(rand)
        {cx, cy} = elem(corners, Int32.to_int32(r * 3))
        x = (x + cx) / 2
        y = (y + cy) / 2
        at = floor(x) + floor(y) * @w
        {Map.put_new(first, at, n), x, y, rand}
      end)

    first
  end

  @impl true
  def frame(state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    u = t + @start
    k = floor(u / @cycle)

    state =
      if k != state.cycle,
        do: %{state | cycle: k, first: build(state.corners, k)},
        else: state

    %{rank: rank, first: first, marks: marks} = state
    tau = u - k * @cycle

    shown =
      if tau >= @fill,
        do: @points,
        else: floor(@steady * tau + state.scale * (:math.exp(@rate * tau) - 1))

    gone = if tau <= @hold, do: 0, else: (tau - @hold) / (@clear - @hold)

    # 1 or 0, for the bit mask below.
    on = fn qx, qy ->
      at = qx + qy * @w
      if elem(rank, at) >= gone and Map.get(first, at, @points - 1) < shown, do: 1, else: 0
    end

    # The corners are marked while the game is being played and once it is over.
    marked = tau < @fill or tau >= @clear

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1) do
          qx = c * 2
          qy = r * 2
          m = on.(qx, qy) + 2 * on.(qx + 1, qy) + 4 * on.(qx, qy + 1) + 8 * on.(qx + 1, qy + 1)

          cond do
            m != 0 -> elem(@quad, m)
            marked and MapSet.member?(marks, c + r * cols) -> "·"
            true -> " "
          end
        end
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
