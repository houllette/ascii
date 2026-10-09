defmodule Ascii.Diagram.Orthogonal do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Text}

  @spec route(
          nodes :: map(),
          groups :: map(),
          edges :: [map()],
          direction :: atom(),
          opts :: keyword()
        ) :: {:ok, [map()]} | Ascii.Diagram.error()
  def route(nodes, groups, edges, direction, opts) do
    headers =
      Enum.map(Map.values(groups), fn b ->
        %{x: b.x + 1, y: b.y, width: b.width - 2, height: length(b.header_lines)}
      end)

    obstacles = Map.values(nodes) ++ headers
    endpoints = Map.merge(groups, nodes)

    definitions =
      Enum.map(edges, fn edge ->
        {from_side, to_side} = sides(edge, Map.get(edge, :route_direction, direction))
        {edge, {edge.from, from_side}, {edge.to, to_side}}
      end)

    counts = definitions |> Enum.flat_map(fn {_, a, b} -> [a, b] end) |> Enum.frequencies()

    {connections, _slots} =
      Enum.map_reduce(definitions, %{}, fn {edge, from, to}, slots ->
        {start, slots} = allocated_port(endpoints, from, counts, slots)
        {finish, slots} = allocated_port(endpoints, to, counts, slots)
        start_lead = lead(start, endpoints[edge.from])
        finish_lead = lead(finish, endpoints[edge.to])
        {{edge, start, finish, start_lead, finish_lead}, slots}
      end)

    guards = Enum.flat_map(connections, fn {_, a, b, c, d} -> [channel(a, c), channel(b, d)] end)

    connections
    |> Enum.reduce_while({:ok, [], obstacles}, fn {edge, start, finish, start_lead, finish_lead},
                                                  {:ok, routed, obstacles} ->
      lines = if edge.label == "", do: [], else: Drawing.wrap(edge.label, opts[:label_width])

      body_obstacles = [prefix(start, start_lead), prefix(finish, finish_lead) | obstacles]

      with true <- clear?(start, start_lead, obstacles) and clear?(finish, finish_lead, obstacles),
           {:ok, points} <- path(start_lead, finish_lead, body_obstacles, routed),
           {:ok, points, label} <-
             labelled(points, start_lead, finish_lead, lines, body_obstacles, routed, guards) do
        points = simplify(Enum.dedup([start | points] ++ [finish]))

        record =
          Map.merge(edge, %{
            points: points,
            label_x: label.x,
            label_y: label.y,
            label_lines: lines
          })

        obstacles = if lines == [], do: obstacles, else: [label | obstacles]
        {:cont, {:ok, routed ++ [record], obstacles}}
      else
        _ -> {:halt, {:error, {:invalid_diagram, {:route, edge.id}}}}
      end
    end)
    |> then(fn
      {:ok, routed, _} -> {:ok, routed}
      error -> error
    end)
  end

  defp sides(%{from: id, to: id}, _direction), do: {:east, :north}
  defp sides(_edge, :lr), do: {:east, :west}
  defp sides(_edge, :rl), do: {:west, :east}
  defp sides(_edge, :tb), do: {:south, :north}
  defp sides(_edge, :bt), do: {:north, :south}

  defp allocated_port(endpoints, {id, side} = key, counts, slots) do
    box = endpoints[id]
    index = Map.get(slots, key, 0)

    point =
      if Map.get(box, :shape) == :entity do
        size = if side in [:east, :west], do: box.height, else: box.width
        offset = div((index + 1) * (size - 1), counts[key] + 1)
        port_offset(box, side, offset)
      else
        port(box, side)
      end

    {point, Map.put(slots, key, index + 1)}
  end

  defp lead({x, y}, box) when x < box.x, do: {x - 2, y}
  defp lead({x, y}, box) when x >= box.x + box.width, do: {x + 2, y}
  defp lead({x, y}, box) when y < box.y, do: {x, y - 2}
  defp lead({x, y}, _box), do: {x, y + 2}

  defp prefix({x, y} = point, {a, b}), do: channel(point, {x + div(a - x, 2), y + div(b - y, 2)})

  defp channel({x, y}, {a, b}),
    do: %{x: min(x, a), y: min(y, b), width: abs(x - a) + 1, height: abs(y - b) + 1}

  defp port(b, side) do
    offset = if side in [:east, :west], do: div(b.height, 2), else: div(b.width, 2)
    port_offset(b, side, offset)
  end

  defp port_offset(b, :east, offset), do: {b.x + b.width, b.y + offset}
  defp port_offset(b, :west, offset), do: {b.x - 1, b.y + offset}
  defp port_offset(b, :north, offset), do: {b.x + offset, b.y - 1}
  defp port_offset(b, :south, offset), do: {b.x + offset, b.y + b.height}

  # Search a compressed visibility grid, never every cell in a large frame.
  # Distance, bends and intersections have deterministic costs.
  defp path(start, finish, obstacles, routed) do
    xs = axis(obstacles, start, finish, :x, :width, 0)
    ys = axis(obstacles, start, finish, :y, :height, 1)

    grid = %{
      xs: List.to_tuple(xs),
      ys: List.to_tuple(ys),
      blocked: blocked(obstacles, xs, ys),
      crossings: crossing_index(routed, xs, ys)
    }

    source =
      {Enum.find_index(xs, &(&1 == elem(start, 0))), Enum.find_index(ys, &(&1 == elem(start, 1))),
       nil}

    target =
      {Enum.find_index(xs, &(&1 == elem(finish, 0))),
       Enum.find_index(ys, &(&1 == elem(finish, 1)))}

    search(
      :gb_sets.singleton({distance(start, finish), 0, source}),
      %{source => 0},
      %{},
      target,
      grid
    )
  end

  defp axis(obstacles, start, finish, coordinate, size, index) do
    values =
      [0, elem(start, index), elem(finish, index)] ++
        Enum.flat_map(obstacles, &[&1[coordinate] - 1, &1[coordinate] + &1[size]])

    values = Enum.filter(values, &(&1 >= 0))
    Enum.sort(Enum.uniq([Enum.max(values) + 3 | values]))
  end

  defp search(queue, scores, previous, target, grid) do
    if :gb_sets.is_empty(queue) do
      :error
    else
      {{_priority, cost, {x, y, _axis} = current}, queue} = :gb_sets.take_smallest(queue)

      cond do
        cost != scores[current] ->
          search(queue, scores, previous, target, grid)

        {x, y} == target ->
          {:ok, reconstruct(current, previous, grid, []) |> simplify()}

        true ->
          {queue, scores, previous} = visit(current, cost, queue, scores, previous, target, grid)
          search(queue, scores, previous, target, grid)
      end
    end
  end

  defp visit({x, y, axis} = current, cost, queue, scores, previous, target, grid) do
    neighbors = [{x - 1, y, :h}, {x + 1, y, :h}, {x, y - 1, :v}, {x, y + 1, :v}]

    Enum.reduce(neighbors, {queue, scores, previous}, fn {nx, ny, next_axis} = next,
                                                         {queue, scores, previous} ->
      if nx >= 0 and ny >= 0 and nx < tuple_size(grid.xs) and ny < tuple_size(grid.ys) do
        a = point(current, grid)
        b = point(next, grid)

        score =
          cost + distance(a, b) + if(axis && axis != next_axis, do: 3, else: 0) +
            intersections(a, b, grid.crossings)

        if score < Map.get(scores, next, :infinity) and grid_clear?(a, b, grid.blocked) do
          priority = score + distance(b, point({elem(target, 0), elem(target, 1), nil}, grid))

          {:gb_sets.add({priority, score, next}, queue), Map.put(scores, next, score),
           Map.put(previous, next, current)}
        else
          {queue, scores, previous}
        end
      else
        {queue, scores, previous}
      end
    end)
  end

  defp point({x, y, _}, grid), do: {elem(grid.xs, x), elem(grid.ys, y)}
  defp distance({x, y}, {a, b}), do: abs(x - a) + abs(y - b)

  defp reconstruct(current, previous, grid, acc) do
    acc = [point(current, grid) | acc]

    case Map.fetch(previous, current) do
      {:ok, before} -> reconstruct(before, previous, grid, acc)
      :error -> acc
    end
  end

  defp simplify(points) do
    points
    |> Enum.reduce([], fn
      point, [b, a | rest] = acc ->
        if collinear?(a, b, point), do: [point, a | rest], else: [point | acc]

      point, acc ->
        [point | acc]
    end)
    |> Enum.reverse()
  end

  defp collinear?({x, a}, {x, b}, {x, c}), do: b >= min(a, c) and b <= max(a, c)
  defp collinear?({a, y}, {b, y}, {c, y}), do: b >= min(a, c) and b <= max(a, c)
  defp collinear?(_a, _b, _c), do: false

  defp clear?(a, b, obstacles), do: not Enum.any?(obstacles, &crosses?(a, b, &1))

  defp crosses?({x, a}, {x, b}, box),
    do:
      x >= box.x and x < box.x + box.width and max(a, b) >= box.y and
        min(a, b) < box.y + box.height

  defp crosses?({a, y}, {b, y}, box),
    do:
      y >= box.y and y < box.y + box.height and max(a, b) >= box.x and
        min(a, b) < box.x + box.width

  defp blocked(obstacles, xs, ys) do
    horizontal =
      Map.new(ys, fn y ->
        {y, for(b <- obstacles, y >= b.y and y < b.y + b.height, do: {b.x, b.x + b.width - 1})}
      end)

    vertical =
      Map.new(xs, fn x ->
        {x, for(b <- obstacles, x >= b.x and x < b.x + b.width, do: {b.y, b.y + b.height - 1})}
      end)

    %{h: horizontal, v: vertical}
  end

  defp grid_clear?({a, y}, {b, y}, blocked), do: clear_interval?(a, b, blocked.h[y])
  defp grid_clear?({x, a}, {x, b}, blocked), do: clear_interval?(a, b, blocked.v[x])

  defp clear_interval?(a, b, intervals),
    do: not Enum.any?(intervals, fn {l, r} -> max(a, b) >= l and min(a, b) <= r end)

  defp crossing_index(routed, xs, ys) do
    segments = Enum.flat_map(routed, &Enum.chunk_every(&1.points, 2, 1, :discard))

    h =
      Map.new(ys, fn y ->
        intervals =
          Enum.flat_map(segments, fn [{ax, ay}, {bx, by}] ->
            if y >= min(ay, by) and y <= max(ay, by), do: [{min(ax, bx), max(ax, bx)}], else: []
          end)

        {y, intervals}
      end)

    v =
      Map.new(xs, fn x ->
        intervals =
          Enum.flat_map(segments, fn [{ax, ay}, {bx, by}] ->
            if x >= min(ax, bx) and x <= max(ax, bx), do: [{min(ay, by), max(ay, by)}], else: []
          end)

        {x, intervals}
      end)

    %{h: h, v: v}
  end

  defp intersections({a, y}, {b, y}, index), do: interval_cost(a, b, index.h[y])
  defp intersections({x, a}, {x, b}, index), do: interval_cost(a, b, index.v[x])

  defp interval_cost(a, b, intervals),
    do: Enum.count(intervals, fn {l, r} -> max(a, b) >= l and min(a, b) <= r end) * 4

  defp labelled(points, _start, _finish, [], _obstacles, _routed, _guards),
    do: {:ok, points, %{x: 0, y: 0, width: 0, height: 0}}

  defp labelled(points, start, finish, lines, obstacles, routed, guards) do
    width = lines |> Enum.map(&Text.width/1) |> Enum.max()
    height = length(lines)

    candidates =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(&label_positions(&1, width, height))

    label =
      Enum.find(candidates, fn b ->
        b.x >= 0 and b.y >= 0 and Enum.all?(obstacles ++ guards, &(not overlap?(b, &1))) and
          Enum.all?(
            [%{points: points} | routed],
            &Enum.all?(Enum.chunk_every(&1.points, 2, 1, :discard), fn [a, c] ->
              not crosses?(a, c, b)
            end)
          )
      end)

    if label do
      {:ok, points, label}
    else
      # A congested diagram gets a dedicated labelled channel at the right.
      points = Enum.flat_map(routed, & &1.points)

      x =
        Enum.max(Enum.map(obstacles, &(&1.x + &1.width)) ++ Enum.map(points, &elem(&1, 0)), fn ->
          0
        end)

      y =
        Enum.max(Enum.map(obstacles, &(&1.y + &1.height)) ++ Enum.map(points, &elem(&1, 1)), fn ->
          0
        end)

      label = %{x: x + 3, y: y + 2, width: width, height: height}
      left = {label.x - 1, label.y + height}
      right = {label.x + width, label.y + height}

      with {:ok, first} <- path(start, left, obstacles, routed),
           {:ok, last} <- path(right, finish, [label | obstacles], routed),
           do: {:ok, simplify(first ++ [right] ++ tl(last)), label}
    end
  end

  defp label_positions([{a, y}, {b, y}], width, height) do
    if abs(b - a) >= width do
      x = div(a + b - width, 2)
      for row <- [y - height, y + 1], do: %{x: x, y: row, width: width, height: height}
    else
      []
    end
  end

  defp label_positions([{x, a}, {x, b}], width, height) do
    if abs(b - a) >= height do
      y = div(a + b - height, 2)
      for col <- [x + 1, x - width], do: %{x: col, y: y, width: width, height: height}
    else
      []
    end
  end

  defp overlap?(a, b),
    do:
      a.x < b.x + b.width and a.x + a.width > b.x and a.y < b.y + b.height and
        a.y + a.height > b.y
end
