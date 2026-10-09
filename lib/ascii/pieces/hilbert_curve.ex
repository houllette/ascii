defmodule Ascii.Pieces.HilbertCurve do
  @moduledoc """
  A closed loop of two hilbert curves, with two lit runners.

  Two Hilbert curves, each through every point of an 8 by 8 grid, joined end
  to end into one closed loop. Two lit runners circle it.

  Ported from `src/pieces/hilbert-curve.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.JSMath
  import Bitwise

  @meta %Ascii.Meta{
    name: "hilbert curve",
    category: :generative,
    note: "a closed loop of two hilbert curves, with two lit runners",
    cols: 65,
    rows: 17,
    fps: 20,
    loop: 16
  }

  # Grid points across and down.
  @gw 16
  @gh 8
  # Characters from one point to the next: a square step.
  @sx 4
  @sy 2
  # The margin round the drawing.
  @ox 2
  @oy 1
  # A runner's heavy stretch, in column widths (a row is two), and its dashed
  # tail behind that.
  @len 30
  @tail 4
  # Column widths a second.
  @speed 16

  # Arms: left 1, right 2, up 4, down 8. For each pair of arms, the glyph with
  # neither, the first, the second or both drawn heavy.
  @l 1
  @r 2
  @u 4
  @d 8
  @glyphs %{
    (@l ||| @r) => {"─", "╾", "╼", "━"},
    (@u ||| @d) => {"│", "╿", "╽", "┃"},
    (@r ||| @d) => {"╭", "┍", "┎", "┏"},
    (@l ||| @d) => {"╮", "┑", "┒", "┓"},
    (@r ||| @u) => {"╰", "┕", "┖", "┗"},
    (@l ||| @u) => {"╯", "┙", "┚", "┛"}
  }
  @first %{
    (@l ||| @r) => @l,
    (@u ||| @d) => @u,
    (@r ||| @d) => @r,
    (@l ||| @d) => @l,
    (@r ||| @u) => @r,
    (@l ||| @u) => @l
  }
  @back %{@l => @r, @r => @l, @u => @d, @d => @u}
  # A straight cell in a tail.
  @dash %{(@l ||| @r) => "╍", (@u ||| @d) => "╏"}

  @impl true
  def meta, do: @meta

  # Jakub Cerveny's generalized Hilbert curve (gilbert2d), for any w by h grid.
  defp gilbert(x, y, ax, ay, bx, by) do
    w = abs(ax + ay)
    h = abs(bx + by)
    [dax, day, dbx, dby] = Enum.map([ax, ay, bx, by], &JSMath.sign/1)

    if h == 1 or w == 1 do
      {dx, dy, n} = if h == 1, do: {dax, day, w}, else: {dbx, dby, h}
      for i <- 0..(n - 1)//1, do: {x + i * dx, y + i * dy}
    else
      [ax2, ay2, bx2, by2] = Enum.map([ax, ay, bx, by], &Integer.floor_div(&1, 2))

      if 2 * w > 3 * h do
        {ax2, ay2} =
          if rem(abs(ax2 + ay2), 2) == 1 and w > 2, do: {ax2 + dax, ay2 + day}, else: {ax2, ay2}

        gilbert(x, y, ax2, ay2, bx, by) ++
          gilbert(x + ax2, y + ay2, ax - ax2, ay - ay2, bx, by)
      else
        {bx2, by2} =
          if rem(abs(bx2 + by2), 2) == 1 and h > 2, do: {bx2 + dbx, by2 + dby}, else: {bx2, by2}

        gilbert(x, y, bx2, by2, ax2, ay2) ++
          gilbert(x + bx2, y + by2, ax, ay, bx - bx2, by - by2) ++
          gilbert(
            x + (ax - dax) + (bx2 - dbx),
            y + (ay - day) + (by2 - dby),
            -bx2,
            -by2,
            -(ax - ax2),
            -(ay - ay2)
          )
      end
    end
  end

  defp dir_of(dx, _dy) when dx < 0, do: @l
  defp dir_of(dx, _dy) when dx > 0, do: @r
  defp dir_of(_dx, dy) when dy < 0, do: @u
  defp dir_of(_dx, _dy), do: @d

  defp half(arm) when (arm &&& (@l ||| @r)) != 0, do: 0.5
  defp half(_arm), do: 1

  @impl true
  def init(_options) do
    # The left half runs down its right edge's side and the right half back up
    # its left edge's, so each ends one step from where the other starts.
    pts =
      gilbert(div(@gw, 2) - 1, 0, 0, @gh, -div(@gw, 2), 0) ++
        gilbert(div(@gw, 2), @gh - 1, 0, -@gh, div(@gw, 2), 0)

    # Every cell the loop passes through, in order, with the arm it comes in
    # by and the arm it leaves by, and where along the loop each arm's middle is.
    pt = List.to_tuple(pts)
    n = tuple_size(pt)

    cells =
      for k <- 0..(n - 1), cell <- walk(pt, k, n), do: cell

    {cells, lap} =
      Enum.map_reduce(cells, 0, fn {r, c, into, out}, d ->
        a = d + half(into) / 2
        d = d + half(into)
        b = d + half(out) / 2
        d = d + half(out)
        {%{r: r, c: c, mask: into ||| out, into: into, a: a, b: b}, d}
      end)

    # For each straight cell, where the next corner ahead of it leaves by.
    ct = List.to_tuple(cells)
    len = tuple_size(ct)

    {corners, _} =
      Enum.reduce((2 * len - 1)..0//-1, {%{}, 0}, fn k, {corners, corner} ->
        cell = elem(ct, rem(k, len))

        if Map.has_key?(@dash, cell.mask),
          do: {Map.put(corners, rem(k, len), corner), corner},
          else: {corners, cell.b}
      end)

    cells =
      cells
      |> Enum.with_index()
      |> Enum.map(fn {cell, i} ->
        {cell.r * @meta.cols + cell.c, cell.mask, @first[cell.mask] == cell.into, cell.a, cell.b,
         Map.get(corners, i)}
      end)

    %{cells: cells, lap: lap}
  end

  defp walk(pt, k, n) do
    {x, y} = elem(pt, k)
    {nx, ny} = elem(pt, rem(k + 1, n))
    {px, py} = elem(pt, rem(k + n - 1, n))
    out = dir_of(nx - x, ny - y)

    {dx, dy} =
      case out do
        @l -> {-1, 0}
        @r -> {1, 0}
        @u -> {0, -1}
        @d -> {0, 1}
      end

    steps = if (out &&& (@l ||| @r)) != 0, do: @sx, else: @sy

    [
      {@oy + y * @sy, @ox + x * @sx, dir_of(px - x, py - y), out}
      | for(
          s <- 1..(steps - 1)//1,
          do: {@oy + y * @sy + dy * s, @ox + x * @sx + dx * s, @back[out], out}
        )
    ]
  end

  # How far behind the nearer runner a point is: 0 at a head, up to half a lap.
  defp behind(at, head, half_lap),
    do: JSMath.mod(JSMath.mod(head - at, half_lap) + half_lap, half_lap)

  defp tail?(b), do: b >= @len and b < @len + @tail

  @impl true
  def frame(%{cells: cells, lap: lap} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    head = 40 + t * @speed
    half_lap = lap / 2

    grid =
      Map.new(cells, fn {at, mask, into_first, a, b, corner} ->
        bi = behind(a, head, half_lap)
        bo = behind(b, head, half_lap)

        # Just behind a runner, straight cells go dashed, a weight between
        # heavy and light. Corners have no dashed form, so a tail stops at one.
        if corner != nil and tail?(bi) and tail?(bo) and
             not tail?(behind(corner, head, half_lap)) do
          {at, @dash[mask]}
        else
          hi = bi < @len
          ho = bo < @len
          {first, second} = if into_first, do: {hi, ho}, else: {ho, hi}
          {at, elem(@glyphs[mask], if(first, do: 1, else: 0) + if(second, do: 2, else: 0))}
        end
      end)

    lines =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: Map.get(grid, r * cols + c, " ")
      end

    {Enum.intersperse(lines, ?\n), nil, state}
  end
end
