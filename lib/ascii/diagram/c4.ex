defmodule Ascii.Diagram.C4 do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Graph, Layout}

  @spec layout(data :: map(), opts :: keyword()) :: Layout.t() | Ascii.Diagram.error()
  def layout(data, opts) do
    nodes =
      Enum.map(data.elements, fn element ->
        lines =
          [element.label, stereotype(element), element.description] |> Enum.reject(&(&1 == ""))

        element
        |> Map.merge(%{label: Enum.join(lines, "\n"), group: element.boundary})
        |> Drawing.node(opts)
      end)

    Graph.layout(
      nodes,
      data.edges,
      data.boundaries,
      :lr,
      opts,
      "C4 #{data.level}: #{length(nodes)} elements, #{length(data.edges)} relationships"
    )
  end

  defp stereotype(element) do
    kind = element.kind |> Atom.to_string() |> String.capitalize()
    external = if element.external, do: "External ", else: ""
    technology = if element.technology == "", do: "", else: ": #{element.technology}"
    "[#{external}#{kind}#{technology}]"
  end
end
