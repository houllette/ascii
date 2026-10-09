defmodule Ascii.Diagram.Flowchart do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Layout, Routes}

  @spec layout(data :: map(), opts :: keyword()) :: Layout.t()
  def layout(data, opts) do
    ranks = ranks(data.nodes, data.edges, %{})
    nodes = Enum.map(data.nodes, &Map.put(Drawing.node(&1, opts), :rank, ranks[&1.id]))
    horizontal? = data.direction in [:lr, :rl]
    layers = nodes |> Enum.group_by(& &1.rank) |> Enum.sort_by(&elem(&1, 0))
    layers = if data.direction in [:rl, :bt], do: Enum.reverse(layers), else: layers
    edge_count = length(data.edges)

    gap =
      if horizontal?,
        do: max(opts[:gap_cols], edge_count * 4 + opts[:label_width] + 6),
        else: max(opts[:gap_rows], edge_count * 4 + 8)

    {nodes, _offset} =
      Enum.reduce(layers, {%{}, 0}, fn {_rank, layer}, {placed, offset} ->
        {placed, _cross} =
          Enum.reduce(layer, {placed, 0}, fn node, {placed, cross} ->
            {x, y} = if horizontal?, do: {offset, cross}, else: {cross, offset}

            cross_size =
              if horizontal?,
                do: node.height + opts[:gap_rows],
                else: node.width + opts[:gap_cols]

            {Map.put(placed, node.id, Map.merge(node, %{x: x, y: y})), cross + cross_size}
          end)

        layer_size =
          layer |> Enum.map(fn n -> if horizontal?, do: n.width, else: n.height end) |> Enum.max()

        {placed, offset + layer_size + gap}
      end)

    {nodes, edges} = Routes.route(nodes, data.edges, data.direction, opts)
    {cols, rows} = Drawing.extent(nodes, edges)
    boxes = Enum.map(data.nodes, &Drawing.box(nodes[&1.id]))
    paths = Enum.map(edges, &Drawing.path/1)
    labels = Enum.flat_map(edges, &Drawing.edge_label/1)

    %Layout{
      cols: cols,
      rows: rows,
      nodes: nodes,
      edges: edges,
      commands: paths ++ boxes ++ labels,
      description: "flowchart: #{length(data.nodes)} nodes, #{length(edges)} relationships"
    }
  end

  # Remove ready nodes in declaration order. A cycle is broken for placement
  # at its first remaining node; every original edge is retained and routed.
  defp ranks([], _edges, ranks), do: ranks

  defp ranks(nodes, edges, ranks) do
    ready =
      Enum.find(nodes, fn node -> Enum.all?(parents(node.id, edges), &Map.has_key?(ranks, &1)) end) ||
        hd(nodes)

    rank = parents(ready.id, edges) |> Enum.map(&Map.get(ranks, &1, -1)) |> Enum.max(fn -> -1 end)
    ranks(Enum.reject(nodes, &(&1.id == ready.id)), edges, Map.put(ranks, ready.id, rank + 1))
  end

  defp parents(id, edges), do: for(e <- edges, e.to == id and e.from != id, do: e.from)
end
