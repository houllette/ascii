defmodule Ascii.Diagram.Routes do
  @moduledoc false
  alias Ascii.Diagram.Drawing

  @spec route(nodes :: map(), edges :: [map()], direction :: atom(), opts :: keyword()) ::
          {map(), [map()]}
  def route(nodes, [], _direction, _opts), do: {nodes, []}

  def route(nodes, edges, direction, opts) do
    horizontal? = direction in [:lr, :rl]
    outer = Enum.count(edges, &outer?(&1, nodes, direction))

    label_height =
      edges |> Enum.map(&length(Drawing.wrap(&1.label, opts[:label_width]))) |> Enum.max()

    opts = Keyword.put(opts, :lane_height, label_height)
    reserve = outer * if horizontal?, do: label_height + 2, else: opts[:label_width] + 3

    {dx, dy} =
      if horizontal?,
        do: {length(edges) * 2 + 3, reserve + label_height + 2},
        else: {reserve + 2, length(edges) * 2 + label_height + 3}

    nodes = Map.new(nodes, fn {id, n} -> {id, translate(n, dx, dy)} end)

    {routes, _outer} =
      edges
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {edge, index}, slot ->
        external? = outer?(edge, nodes, direction)
        from = nodes[edge.from]
        to = nodes[edge.to]
        from = Map.put(from, :layer_bounds, layer_bounds(from, nodes))
        to = Map.put(to, :layer_bounds, layer_bounds(to, nodes))
        lines = Drawing.wrap(edge.label, opts[:label_width])
        {points, lx, ly} = points(from, to, direction, index, slot, external?, lines, opts)
        routed = Map.merge(edge, %{points: points, label_x: lx, label_y: ly, label_lines: lines})
        {routed, slot + if(external?, do: 1, else: 0)}
      end)

    {nodes, routes}
  end

  defp outer?(edge, nodes, direction) do
    from = nodes[edge.from]
    to = nodes[edge.to]

    from.id == to.id or Map.get(to, :rank, 0) != Map.get(from, :rank, 0) + 1 or
      not forward?(from, to, direction)
  end

  defp forward?(from, to, :lr), do: from.x + from.width < to.x
  defp forward?(from, to, :rl), do: to.x + to.width < from.x
  defp forward?(from, to, :tb), do: from.y + from.height < to.y
  defp forward?(from, to, :bt), do: to.y + to.height < from.y

  defp layer_bounds(node, nodes) do
    layer =
      nodes |> Map.values() |> Enum.filter(&(Map.get(&1, :rank, 0) == Map.get(node, :rank, 0)))

    padding = layer |> Enum.map(&Map.get(&1, :route_padding, 0)) |> Enum.max()

    bounds =
      Enum.map(layer, fn n ->
        Map.get(n, :route_bounds, %{
          left: n.x,
          right: n.x + n.width,
          top: n.y,
          bottom: n.y + n.height
        })
      end)

    %{
      left: Enum.min(Enum.map(bounds, & &1.left)) - padding,
      right: Enum.max(Enum.map(bounds, & &1.right)) + padding,
      top: Enum.min(Enum.map(bounds, & &1.top)),
      bottom: Enum.max(Enum.map(bounds, & &1.bottom))
    }
  end

  defp translate(%{route_bounds: b} = node, dx, dy) do
    %{
      node
      | x: node.x + dx,
        y: node.y + dy,
        route_bounds: %{
          left: b.left + dx,
          right: b.right + dx,
          top: b.top + dy,
          bottom: b.bottom + dy
        }
    }
  end

  defp translate(node, dx, dy), do: %{node | x: node.x + dx, y: node.y + dy}

  defp points(from, to, direction, index, slot, outer?, lines, opts)
       when direction in [:lr, :rl] do
    sign = if direction == :lr, do: 1, else: -1
    sx = if sign == 1, do: from.x + from.width, else: from.x - 1
    ex = if sign == 1, do: to.x - 1, else: to.x + to.width
    sy = from.y + div(from.height, 2)
    ey = to.y + div(to.height, 2)
    source_side = if sign == 1, do: from.layer_bounds.right, else: from.layer_bounds.left - 1
    target_side = if sign == 1, do: to.layer_bounds.left - 1, else: to.layer_bounds.right
    rail = source_side + sign * (index * 2 + 1)

    if outer? do
      target_rail = target_side - sign * (index * 2 + 1)
      lane = slot * (opts[:lane_height] + 2) + opts[:lane_height]

      points = [
        {sx, sy},
        {rail, sy},
        {rail, lane},
        {target_rail, lane},
        {target_rail, ey},
        {ex, ey}
      ]

      {points, max(min(rail, target_rail) + 1, 0), lane - length(lines)}
    else
      points = [{sx, sy}, {rail, sy}, {rail, ey}, {ex, ey}]
      label_x = if sign == 1, do: rail + 1, else: ex + 1
      {points, label_x, max(min(sy, ey) - length(lines), 0)}
    end
  end

  defp points(from, to, direction, index, slot, outer?, lines, opts) do
    sign = if direction == :tb, do: 1, else: -1
    sy = if sign == 1, do: from.y + from.height, else: from.y - 1
    ey = if sign == 1, do: to.y - 1, else: to.y + to.height
    sx = from.x + div(from.width, 2)
    ex = to.x + div(to.width, 2)
    source_side = if sign == 1, do: from.layer_bounds.bottom, else: from.layer_bounds.top - 1
    target_side = if sign == 1, do: to.layer_bounds.top - 1, else: to.layer_bounds.bottom
    rail = source_side + sign * (index * 2 + length(lines) + 1)

    if outer? do
      target_rail = target_side - sign * (index * 2 + 1)
      lane = slot * (opts[:label_width] + 3)

      points = [
        {sx, sy},
        {sx, rail},
        {lane, rail},
        {lane, target_rail},
        {ex, target_rail},
        {ex, ey}
      ]

      {points, lane + 1, min(rail, target_rail)}
    else
      points = [{sx, sy}, {sx, rail}, {ex, rail}, {ex, ey}]
      {points, max(sx, ex) + 2, rail - length(lines)}
    end
  end
end
