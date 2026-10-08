defmodule AsciiArt.Pieces.Maze do
  @moduledoc """
  A maze carved by backtracking, then solved, then remade.

  A recursive backtracker carving a maze out of a grid, its stack shown as a
  dotted trail, then the way through drawn in, then the walls close up and a
  new maze starts.

  Ported from `src/pieces/maze.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  import Bitwise

  @meta %AsciiArt.Meta{
    name: "maze",
    category: :generative,
    note: "a maze carved by backtracking, then solved, then remade",
    cols: 61,
    rows: 21,
    fps: 20
  }

  # Cells across and down; four columns by two rows each.
  @mw 15
  @mh 10
  @cells @mw * @mh
  # Backtracker moves a second.
  @carve 40
  # Seconds to draw the way through, to hold it, and for the walls to sweep back.
  @solve 2.4
  @hold 2.2
  @close 1.2
  # Where in the first cycle play time begins, in seconds.
  @start 5.2
  # The backtracker steps into every cell but the first once and back once.
  @carved 2 * (@cells - 1) / @carve
  @period @carved + @solve + @hold + @close

  @l 1
  @r 2
  @u 4
  @d 8
  @join {" ", "╴", "╶", "─", "╵", "┘", "└", "┴", "╷", "┐", "┌", "┬", "│", "┤", "├", "┼"}
  @path %{
    (@l ||| @r) => "━",
    (@u ||| @d) => "┃",
    (@r ||| @d) => "┏",
    (@l ||| @d) => "┓",
    (@r ||| @u) => "┗",
    (@l ||| @u) => "┛"
  }

  @impl true
  def meta, do: @meta

  # The mazes are a pure function of their number; the last few are kept.
  @impl true
  def init(_options), do: %{}

  defp get(cache, n) do
    case cache do
      %{^n => maze} ->
        {maze, cache}

      _ ->
        maze = build(1009 + n * 7919)

        cache =
          if map_size(cache) > 2,
            do: Map.delete(cache, cache |> Map.keys() |> Enum.min()),
            else: cache

        {maze, Map.put(cache, n, maze)}
    end
  end

  # The backtracker's moves for one maze: n steps forward into cell n, -1 steps
  # back. Then the way from the top left cell to the bottom right one.
  defp build(seed) do
    {moves, parent} = carve([0], %{0 => true}, %{}, [], Int32.to_int32(seed))
    %{moves: List.to_tuple(moves), way: way([@cells - 1], parent)}
  end

  defp carve([], _seen, parent, moves, _rand), do: {Enum.reverse(moves), parent}

  defp carve([c | rest] = stack, seen, parent, moves, rand) do
    x = rem(c, @mw)
    y = div(c, @mw)

    next =
      [
        {x > 0, c - 1},
        {x < @mw - 1, c + 1},
        {y > 0, c - @mw},
        {y < @mh - 1, c + @mw}
      ]
      |> Enum.filter(fn {ok, n} -> ok and not Map.has_key?(seen, n) end)
      |> Enum.map(&elem(&1, 1))

    case next do
      [] ->
        moves = if rest == [], do: moves, else: [-1 | moves]
        carve(rest, seen, parent, moves, rand)

      _ ->
        {r, rand} = Int32.mulberry32(rand)
        n = Enum.at(next, floor(r * length(next)))
        carve([n | stack], Map.put(seen, n, true), Map.put(parent, n, c), [n | moves], rand)
    end
  end

  defp way([0 | _] = way, _parent), do: way
  defp way([n | _] = way, parent), do: way([Map.fetch!(parent, n) | way], parent)

  defp centre(n), do: {2 * div(n, @mw) + 1, 4 * rem(n, @mw) + 2}

  # The board after the first k moves: the walls opened (above each cell, and
  # left of each cell), each cell's state (absent untouched, 1 on the stack, 2
  # done) and the stack, top first.
  defp replay(moves, k) do
    # The way in, top left, and out, bottom right.
    open = {MapSet.new(), MapSet.new([0, (@mh - 1) * (@mw + 1) + @mw])}

    {{h, v}, state, stack} =
      Enum.reduce(0..(k - 1)//1, {open, %{0 => 1}, [0]}, fn i,
                                                            {{h, v}, state, [c | rest] = stack} ->
        case elem(moves, i) do
          mv when mv < 0 ->
            {{h, v}, Map.put(state, c, 2), rest}

          mv ->
            walls =
              case mv - c do
                1 -> {h, MapSet.put(v, div(c, @mw) * (@mw + 1) + rem(c, @mw) + 1)}
                -1 -> {h, MapSet.put(v, div(c, @mw) * (@mw + 1) + rem(c, @mw))}
                @mw -> {MapSet.put(h, mv), v}
                _ -> {MapSet.put(h, c), v}
              end

            {walls, Map.put(state, mv, 1), [mv | stack]}
        end
      end)

    state = if k >= tuple_size(moves), do: Map.put(state, 0, 2), else: state
    {h, v, state, stack}
  end

  defp draw(maze, k, solved) do
    %{cols: cols, rows: rows} = @meta
    {h, v, state, stack} = replay(maze.moves, k)
    h? = &(not MapSet.member?(h, &1))
    v? = &(not MapSet.member?(v, &1))

    grid =
      for j <- 0..@mh, i <- 0..@mw, reduce: %{} do
        grid ->
          arms =
            bor(
              bor(
                if(i > 0 and h?.(j * @mw + i - 1), do: @l, else: 0),
                if(i < @mw and h?.(j * @mw + i), do: @r, else: 0)
              ),
              bor(
                if(j > 0 and v?.((j - 1) * (@mw + 1) + i), do: @u, else: 0),
                if(j < @mh and v?.(j * (@mw + 1) + i), do: @d, else: 0)
              )
            )

          grid = put(grid, 2 * j, 4 * i, elem(@join, arms))

          grid =
            if i < @mw and h?.(j * @mw + i),
              do: Enum.reduce(1..3, grid, &put(&2, 2 * j, 4 * i + &1, "─")),
              else: grid

          if j < @mh and v?.(j * (@mw + 1) + i), do: put(grid, 2 * j + 1, 4 * i, "│"), else: grid
      end

    grid =
      Enum.reduce(0..(@cells - 1), grid, fn n, grid ->
        if Map.has_key?(state, n), do: grid, else: block(grid, n, "░")
      end)

    grid = if k < tuple_size(maze.moves), do: trail(grid, stack), else: grid
    grid = if solved > 0, do: way_through(grid, maze.way, solved), else: grid

    for r <- 0..(rows - 1) do
      for c <- 0..(cols - 1), do: Map.get(grid, r * cols + c, " ")
    end
  end

  defp put(grid, r, c, ch), do: Map.put(grid, r * @meta.cols + c, ch)

  defp block(grid, n, ch) do
    {r, c} = centre(n)
    grid |> put(r, c - 1, ch) |> put(r, c, ch) |> put(r, c + 1, ch)
  end

  # The stack as a dotted trail, through each cell and each opening.
  defp trail(grid, [top | _] = stack) do
    {grid, _} =
      stack
      |> Enum.reverse()
      |> Enum.reduce({grid, nil}, fn n, {grid, prev} ->
        {r, c} = centre(n)
        grid = put(grid, r, c, "·")

        case prev do
          nil ->
            {grid, n}

          _ ->
            {r0, c0} = centre(prev)
            {put(grid, div(r + r0, 2), div(c + c0, 2), "·"), n}
        end
      end)

    block(grid, top, "█")
  end

  # The way through, drawn in from the entrance as far as `solved` (0 to 1).
  defp way_through(grid, way, solved) do
    cols = @meta.cols
    pts = [{1, -1}] ++ Enum.map(way, &centre/1) ++ [{2 * @mh - 1, cols}]

    cells =
      pts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [{r0, c0}, {r1, c1}] ->
        dr = JSMath.sign(r1 - r0)
        dc = JSMath.sign(c1 - c0)
        n = max(abs(r1 - r0), abs(c1 - c0))
        for s <- 1..n, do: {r0 + dr * s, c0 + dc * s, dr, dc}
      end)

    shown = JSMath.round(solved * length(cells))

    cells
    |> Enum.take(shown)
    |> Enum.with_index(1)
    |> Enum.zip(tl(cells) ++ [nil])
    |> Enum.reduce(grid, fn {{{r, c, dr, dc}, q1}, next}, grid ->
      if c < 0 or c >= cols do
        grid
      else
        into = arm_in(dr, dc)

        out =
          if next == nil or q1 >= shown,
            do: band(if((into &&& (@l ||| @r)) != 0, do: @l ||| @r, else: @u ||| @d), bnot(into)),
            else: arm_out(next)

        put(grid, r, c, Map.get(@path, into ||| out, "━"))
      end
    end)
  end

  defp arm_in(_dr, dc) when dc > 0, do: @l
  defp arm_in(_dr, dc) when dc < 0, do: @r
  defp arm_in(dr, _dc) when dr > 0, do: @u
  defp arm_in(_dr, _dc), do: @d

  defp arm_out({_, _, _, dc}) when dc > 0, do: @r
  defp arm_out({_, _, _, dc}) when dc < 0, do: @l
  defp arm_out({_, _, dr, _}) when dr > 0, do: @d
  defp arm_out(_next), do: @u

  @impl true
  def frame(cache, t, _env) do
    # Which maze is playing, and how far into it.
    n = floor((t + @start) / @period)
    p = t + @start - n * @period
    {maze, cache} = get(cache, n)
    k = min(tuple_size(maze.moves), floor(p * @carve))
    solved = min(1, max(0, (p - @carved) / @solve))
    now = draw(maze, k, solved)
    close = (p - @carved - @solve - @hold) / @close

    {lines, cache} =
      if close <= 0 do
        {now, cache}
      else
        # The walls sweep back in from the left a column of cells at a time,
        # ready for the next maze.
        {next, cache} = get(cache, n + 1)
        fresh = draw(next, 0, 0)
        edge = 4 * min(@mw, floor(close * (@mw + 1))) + 1

        {Enum.zip_with(fresh, now, fn f, line -> Enum.take(f, edge) ++ Enum.drop(line, edge) end),
         cache}
      end

    {Enum.intersperse(lines, ?\n), nil, cache}
  end
end
