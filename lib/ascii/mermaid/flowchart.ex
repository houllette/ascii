defmodule Ascii.Mermaid.Flowchart do
  @moduledoc false
  alias Ascii.{Diagram, Mermaid.Syntax}
  alias Ascii.Diagram.Style
  alias Ascii.Mermaid.Styles

  @spec parse(statements :: [Syntax.position()], direction :: atom(), header :: Syntax.position()) ::
          {:ok, Diagram.t()} | Ascii.Mermaid.error()
  def parse(statements, direction, header) do
    result =
      Enum.reduce_while(statements, {:ok, [], []}, fn {text, _, _} = position,
                                                      {:ok, nodes, edges} ->
        case statement(text, nodes, edges) do
          {:ok, nodes, edges} ->
            {:cont, {:ok, nodes, edges}}

          :error ->
            {:halt, Syntax.error(position, "unsupported or malformed flowchart statement")}
        end
      end)

    case result do
      {:ok, nodes, edges} ->
        Syntax.checked(
          Diagram.flowchart(nodes, edges, direction: direction),
          List.last(statements, header)
        )

      failure ->
        failure
    end
  end

  defp statement("style " <> rest, nodes, edges) do
    with [_, id, css] <- Regex.run(~r/\A([A-Za-z_][A-Za-z0-9_-]*)\s+(.+)\z/s, rest),
         {:ok, style} <- Styles.css(css, :node),
         {:ok, nodes} <- Style.apply_records(nodes, id, style) do
      {:ok, nodes, edges}
    else
      _ -> :error
    end
  end

  defp statement("linkStyle " <> rest, nodes, edges) do
    with [_, index, css] <- Regex.run(~r/\A([0-9]+)\s+(.+)\z/s, rest),
         index = String.to_integer(index),
         true <- index < length(edges),
         {:ok, style} <- Styles.css(css, :edge) do
      {:ok, nodes, List.update_at(edges, index, &Map.merge(&1, style))}
    else
      _ -> :error
    end
  end

  defp statement(text, nodes, edges) do
    with {:ok, node, rest, explicit?} <- parse_node(text) do
      nodes = remember(nodes, node, explicit?)
      chain(node, rest, nodes, edges)
    end
  end

  defp chain(_from, "", nodes, edges), do: {:ok, nodes, edges}

  defp chain(from, rest, nodes, edges) do
    with {:ok, edge, rest} <- edge(rest),
         {:ok, to, rest, explicit?} <- parse_node(rest) do
      edge = Map.merge(edge, %{from: from.id, to: to.id})
      chain(to, rest, remember(nodes, to, explicit?), edges ++ [edge])
    end
  end

  defp parse_node(text) do
    with {:ok, id, rest} <- Syntax.identifier(text), do: shape(id, rest)
  end

  defp shape(id, <<opening, rest::binary>>) when opening in [?[, ?(, ?{] do
    {closing, shape} =
      case opening do
        ?[ -> {?], :rectangle}
        ?( -> {?), :rounded}
        ?{ -> {?}, :diamond}
      end

    with {:ok, label, rest} <- Syntax.delimited(rest, closing),
         {:ok, label} <- Syntax.label(label),
         do: {:ok, %{id: id, label: label, shape: shape}, rest, true}
  end

  defp shape(id, rest), do: {:ok, %{id: id, label: id, shape: :rectangle}, rest, false}

  defp remember(nodes, node, false) do
    if Enum.any?(nodes, &(&1.id == node.id)), do: nodes, else: nodes ++ [node]
  end

  defp remember(nodes, node, true) do
    previous = Enum.find(nodes, &(&1.id == node.id)) || %{}
    Syntax.upsert(nodes, Map.merge(previous, node))
  end

  defp edge("-->" <> rest), do: edge_label(rest, :solid, true)
  defp edge("---" <> rest), do: edge_label(rest, :solid, false)
  defp edge("-.->" <> rest), do: edge_label(rest, :dashed, true)
  defp edge(_rest), do: :error

  defp edge_label(rest, style, arrow) do
    rest = String.trim_leading(rest)

    case rest do
      "|" <> rest ->
        with {:ok, label, rest} <- Syntax.delimited(rest, ?|),
             {:ok, label} <- Syntax.label(label),
             do: {:ok, %{label: label, style: style, arrow: arrow}, rest}

      _ ->
        {:ok, %{label: "", style: style, arrow: arrow}, rest}
    end
  end
end
