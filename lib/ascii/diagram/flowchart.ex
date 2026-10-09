defmodule Ascii.Diagram.Flowchart do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Graph, Layout}

  @spec layout(data :: map(), opts :: keyword()) :: Layout.t() | Ascii.Diagram.error()
  def layout(data, opts) do
    nodes = Enum.map(data.nodes, &Drawing.node(&1, opts))

    Graph.layout(
      nodes,
      data.edges,
      data.groups,
      data.direction,
      opts,
      "flowchart: #{length(nodes)} nodes, #{length(data.edges)} relationships"
    )
  end
end
