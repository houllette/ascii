defmodule Ascii.Diagram.C4 do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Layout, Routes, Text}

  @spec layout(data :: map(), opts :: keyword()) :: Layout.t()
  def layout(data, opts) do
    nodes =
      Map.new(data.elements, fn element ->
        lines =
          [element.label, stereotype(element), element.description] |> Enum.reject(&(&1 == ""))

        node = Drawing.node(Map.put(element, :label, Enum.join(lines, "\n")), opts)
        {node.id, node}
      end)

    definitions = Map.new(data.boundaries, &{&1.id, &1})
    gap = max(opts[:gap_cols], length(data.edges) * 4 + opts[:label_width] + 8)

    {placed, boundaries, _x} =
      units(data, nil, definitions)
      |> Enum.with_index()
      |> Enum.reduce({%{}, %{}, 0}, fn {unit, rank}, {placed, boundaries, x} ->
        group = group(unit, data, nodes, definitions, opts) |> translate(x, 0)
        bounds = %{left: x, right: x + group.width, top: 0, bottom: group.height}

        members =
          Map.new(group.nodes, fn {id, node} ->
            {id, Map.merge(node, %{rank: rank, route_bounds: bounds, route_padding: 1})}
          end)

        {Map.merge(placed, members), Map.merge(boundaries, group.boundaries),
         x + group.width + gap}
      end)

    original = placed
    {placed, edges} = Routes.route(placed, data.edges, :lr, opts)
    first = hd(data.elements).id
    dx = placed[first].x - original[first].x
    dy = placed[first].y - original[first].y
    boundaries = Map.new(boundaries, fn {id, b} -> {id, %{b | x: b.x + dx, y: b.y + dy}} end)
    {cols, rows} = Drawing.extent(placed, edges, boundaries)
    boxes = Enum.map(data.elements, &Drawing.box(placed[&1.id]))

    borders =
      boundaries
      |> Map.values()
      |> Enum.sort_by(&(-&1.width * &1.height))
      |> Enum.map(&{:boundary, &1})

    paths = Enum.map(edges, &Drawing.path/1)
    labels = Enum.flat_map(edges, &Drawing.edge_label/1)

    %Layout{
      cols: cols,
      rows: rows,
      nodes: placed,
      boundaries: boundaries,
      edges: edges,
      commands: borders ++ paths ++ boxes ++ labels,
      description: "C4 #{data.level}: #{map_size(nodes)} elements, #{length(edges)} relationships"
    }
  end

  defp group({:node, id}, _data, nodes, _definitions, _opts) do
    node = Map.merge(nodes[id], %{x: 0, y: 0})
    %{nodes: %{id => node}, boundaries: %{}, width: node.width, height: node.height}
  end

  defp group({:boundary, id}, data, nodes, definitions, opts) do
    header_lines = Drawing.wrap(definitions[id].label, opts[:label_width])
    top = length(header_lines) + 2

    {placed, nested, width, y} =
      units(data, id, definitions)
      |> Enum.reduce({%{}, %{}, 3, top}, fn unit, {placed, nested, width, y} ->
        child = group(unit, data, nodes, definitions, opts) |> translate(3, y)

        {Map.merge(placed, child.nodes), Map.merge(nested, child.boundaries),
         max(width, child.width), y + child.height + opts[:gap_rows]}
      end)

    width = max(width + 6, Enum.max(Enum.map(header_lines, &Text.width/1)) + 6)
    height = max(y - opts[:gap_rows] + 3, top + 3)

    boundary =
      Map.merge(definitions[id], %{
        x: 0,
        y: 0,
        width: width,
        height: height,
        header_lines: header_lines
      })

    %{nodes: placed, boundaries: Map.put(nested, id, boundary), width: width, height: height}
  end

  defp units(data, parent, definitions) do
    from_elements =
      Enum.flat_map(data.elements, fn element ->
        if element.boundary == parent do
          [{:node, element.id}]
        else
          case ancestor(element.boundary, parent, definitions) do
            nil -> []
            id -> [{:boundary, id}]
          end
        end
      end)

    children = for b <- data.boundaries, b.parent == parent, do: {:boundary, b.id}
    Enum.uniq(from_elements ++ children)
  end

  defp ancestor(nil, _parent, _definitions), do: nil

  defp ancestor(id, parent, definitions) do
    if definitions[id].parent == parent,
      do: id,
      else: ancestor(definitions[id].parent, parent, definitions)
  end

  defp translate(group, dx, dy),
    do: %{group | nodes: shift(group.nodes, dx, dy), boundaries: shift(group.boundaries, dx, dy)}

  defp shift(bounds, dx, dy),
    do: Map.new(bounds, fn {id, b} -> {id, %{b | x: b.x + dx, y: b.y + dy}} end)

  defp stereotype(element) do
    kind = element.kind |> Atom.to_string() |> String.capitalize()
    external = if element.external, do: "External ", else: ""
    technology = if element.technology == "", do: "", else: ": #{element.technology}"
    "[#{external}#{kind}#{technology}]"
  end
end
