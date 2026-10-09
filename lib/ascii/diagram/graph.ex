defmodule Ascii.Diagram.Graph do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Layout, Orthogonal, Text}

  @spec layout(
          nodes :: [map()],
          edges :: [map()],
          groups :: [map()],
          direction :: atom(),
          opts :: keyword(),
          description :: String.t()
        ) :: Layout.t() | Ascii.Diagram.error()
  def layout(nodes, edges, groups, direction, opts, description) do
    context = %{
      nodes: nodes,
      edges: edges,
      groups: groups,
      definitions: Map.new(groups, &{&1.id, &1}),
      opts: opts
    }

    placed = place(context, nil, direction)

    margin =
      edges
      |> Enum.map(&length(Drawing.wrap(&1.label, opts[:label_width])))
      |> Enum.max(fn -> 0 end)

    placed =
      translate(placed, if(edges == [], do: 0, else: 4), if(edges == [], do: 0, else: margin + 4))

    edges =
      Enum.map(edges, &Map.put(&1, :route_direction, route_direction(&1, context, direction)))

    with {:ok, routed} <-
           Orthogonal.route(placed.nodes, placed.boundaries, edges, direction, opts) do
      {cols, rows} = Drawing.extent(placed.nodes, routed, placed.boundaries)

      borders =
        placed.boundaries
        |> Map.values()
        |> Enum.sort_by(&{-&1.width * &1.height, &1.id})
        |> Enum.map(&{:boundary, &1})

      boxes = Enum.map(nodes, &Drawing.box(placed.nodes[&1.id]))

      %Layout{
        cols: cols,
        rows: rows,
        nodes: placed.nodes,
        boundaries: placed.boundaries,
        edges: routed,
        commands:
          borders ++
            Enum.map(routed, &Drawing.path/1) ++
            boxes ++ Enum.flat_map(routed, &Drawing.edge_label/1),
        description: description
      }
    end
  end

  defp route_direction(edge, context, default) do
    from = ancestors(edge.from, context)
    to = ancestors(edge.to, context)
    shared = Enum.find(from, &(&1 in to))
    inherited_direction(shared, context.definitions, default)
  end

  defp ancestors(id, context) do
    parent =
      case Map.fetch(context.definitions, id) do
        {:ok, group} -> group.parent
        :error -> Enum.find(context.nodes, &(&1.id == id)).group
      end

    lineage(parent, context.definitions)
  end

  defp lineage(nil, _definitions), do: []
  defp lineage(id, definitions), do: [id | lineage(definitions[id].parent, definitions)]
  defp inherited_direction(nil, _definitions, default), do: default

  defp inherited_direction(id, definitions, default),
    do:
      Map.get(definitions[id], :direction) ||
        inherited_direction(definitions[id].parent, definitions, default)

  defp place(context, parent, inherited) do
    direction =
      if parent,
        do: Map.get(context.definitions[parent], :direction) || inherited,
        else: inherited

    units = units(context, parent)
    edges = project_edges(context, parent)
    ranks = ranks(units, edges, %{})
    children = Map.new(units, fn id -> {id, child(context, id, direction)} end)
    layers = units |> Enum.group_by(&ranks[&1]) |> Enum.sort_by(&elem(&1, 0)) |> order(edges)
    layers = if direction in [:rl, :bt], do: Enum.reverse(layers), else: layers
    horizontal? = direction in [:lr, :rl]

    {group, _offset} =
      Enum.reduce(layers, {empty(), 0}, fn {rank, ids}, {result, offset} ->
        {layer, _cross} =
          Enum.reduce(ids, {empty(), 0}, fn id, {layer, cross} ->
            item = children[id]
            {x, y} = if horizontal?, do: {offset, cross}, else: {cross, offset}

            step =
              if horizontal?,
                do: item.height + context.opts[:gap_rows],
                else: item.width + context.opts[:gap_cols]

            {merge(layer, translate(item, x, y)), cross + step}
          end)

        size =
          ids
          |> Enum.map(fn id ->
            if horizontal?, do: children[id].width, else: children[id].height
          end)
          |> Enum.max()

        adjacent = Enum.filter(edges, &(ranks[&1.from] == rank or ranks[&1.to] == rank))

        label_space =
          adjacent
          |> Enum.map(fn edge ->
            lines = Drawing.wrap(edge.label, context.opts[:label_width])

            if horizontal?,
              do: Enum.max(Enum.map(lines, &Text.width/1)) + 6,
              else: length(lines) + 3
          end)
          |> Enum.max(fn -> 0 end)

        gap =
          max(
            if(horizontal?, do: context.opts[:gap_cols], else: context.opts[:gap_rows]),
            label_space
          )
          |> max(7)

        {merge(result, layer), offset + size + gap}
      end)

    enclose(group, parent, context)
  end

  defp child(context, id, direction) do
    if Map.has_key?(context.definitions, id) do
      place(context, id, direction)
    else
      node = Enum.find(context.nodes, &(&1.id == id)) |> Map.merge(%{x: 0, y: 0})
      %{nodes: %{id => node}, boundaries: %{}, width: node.width, height: node.height}
    end
  end

  defp enclose(group, nil, _context), do: group

  defp enclose(group, id, context) do
    definition = context.definitions[id]
    lines = Drawing.wrap(definition.label, context.opts[:label_width])
    group = translate(group, 3, length(lines) + 2)
    width = max(group.width + 3, Enum.max(Enum.map(lines, &Text.width/1)) + 6)
    height = max(group.height + 2, length(lines) + 5)

    boundary =
      Map.merge(definition, %{x: 0, y: 0, width: width, height: height, header_lines: lines})

    %{group | boundaries: Map.put(group.boundaries, id, boundary), width: width, height: height}
  end

  defp units(context, parent) do
    nodes =
      Enum.flat_map(context.nodes, fn node ->
        case projected(node.id, parent, context) do
          nil -> []
          id -> [id]
        end
      end)

    groups = for group <- context.groups, group.parent == parent, do: group.id
    Enum.uniq(nodes ++ groups)
  end

  defp projected(id, parent, context) do
    case Map.fetch(context.definitions, id) do
      {:ok, group} ->
        ancestor(id, group.parent, parent, context.definitions)

      :error ->
        node = Enum.find(context.nodes, &(&1.id == id))
        ancestor(id, node.group, parent, context.definitions)
    end
  end

  defp ancestor(id, parent, parent, _definitions), do: id
  defp ancestor(_id, nil, _parent, _definitions), do: nil

  defp ancestor(_id, group, parent, definitions),
    do: ancestor(group, definitions[group].parent, parent, definitions)

  defp project_edges(context, parent) do
    Enum.flat_map(context.edges, fn edge ->
      from = projected(edge.from, parent, context)
      to = projected(edge.to, parent, context)
      if from && to && from != to, do: [%{edge | from: from, to: to}], else: []
    end)
  end

  defp ranks([], _edges, ranks), do: ranks

  defp ranks(ids, edges, ranks) do
    ready =
      Enum.find(ids, fn id -> Enum.all?(parents(id, edges), &Map.has_key?(ranks, &1)) end) ||
        hd(ids)

    rank = parents(ready, edges) |> Enum.map(&Map.get(ranks, &1, -1)) |> Enum.max(fn -> -1 end)
    ranks(List.delete(ids, ready), edges, Map.put(ranks, ready, rank + 1))
  end

  defp parents(id, edges), do: for(edge <- edges, edge.to == id, do: edge.from)

  # Stable barycentre sweeps reduce crossings; ties retain declaration order.
  defp order(layers, edges) do
    layers = sweep(layers, edges, :from, :to)
    layers |> Enum.reverse() |> sweep(edges, :to, :from) |> Enum.reverse()
  end

  defp sweep(layers, edges, source, target) do
    {layers, _positions} =
      Enum.map_reduce(layers, %{}, fn {rank, ids}, positions ->
        ordered =
          ids
          |> Enum.with_index()
          |> Enum.sort_by(fn {id, index} ->
            peers =
              for e <- edges,
                  e[target] == id,
                  Map.has_key?(positions, e[source]),
                  do: positions[e[source]]

            score = if peers == [], do: index * 1.0, else: Enum.sum(peers) / length(peers)
            {score, index}
          end)
          |> Enum.map(&elem(&1, 0))

        {{rank, ordered}, Map.merge(positions, Map.new(Enum.with_index(ordered)))}
      end)

    layers
  end

  defp empty, do: %{nodes: %{}, boundaries: %{}, width: 0, height: 0}

  defp merge(a, b),
    do: %{
      nodes: Map.merge(a.nodes, b.nodes),
      boundaries: Map.merge(a.boundaries, b.boundaries),
      width: max(a.width, b.width),
      height: max(a.height, b.height)
    }

  defp translate(group, dx, dy),
    do: %{
      group
      | nodes: shift(group.nodes, dx, dy),
        boundaries: shift(group.boundaries, dx, dy),
        width: group.width + dx,
        height: group.height + dy
    }

  defp shift(bounds, dx, dy),
    do: Map.new(bounds, fn {id, b} -> {id, %{b | x: b.x + dx, y: b.y + dy}} end)
end
