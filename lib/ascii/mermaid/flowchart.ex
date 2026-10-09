defmodule Ascii.Mermaid.Flowchart do
  @moduledoc false
  alias Ascii.{Diagram, Mermaid.Syntax}
  alias Ascii.Diagram.Style
  alias Ascii.Mermaid.Styles

  @spec parse(statements :: [Syntax.position()], direction :: atom(), header :: Syntax.position()) ::
          {:ok, Diagram.t()} | Ascii.Mermaid.error()
  def parse(statements, direction, header) do
    initial = %{nodes: [], edges: [], groups: [], stack: [], direction: direction}

    result =
      Enum.reduce_while(statements, {:ok, initial}, fn position, {:ok, state} ->
        case grouped(position, state) do
          {:ok, state} -> {:cont, {:ok, state}}
          _ -> {:halt, Syntax.error(position, "unsupported or malformed flowchart statement")}
        end
      end)

    case result do
      {:ok, %{stack: []} = state} ->
        group_ids = MapSet.new(state.groups, & &1.id)

        if Enum.any?(state.nodes, &(&1.declared and MapSet.member?(group_ids, &1.id))) do
          Syntax.error(List.last(statements, header), "node and subgraph IDs must be distinct")
        else
          nodes =
            state.nodes
            |> Enum.reject(&MapSet.member?(group_ids, &1.id))
            |> Enum.map(&Map.delete(&1, :declared))

          groups =
            Enum.map(state.groups, fn group ->
              previous = Enum.find(state.nodes, &(&1.id == group.id)) || %{}
              Map.merge(Map.take(previous, Style.fields()), group)
            end)

          Syntax.checked(
            Diagram.flowchart(nodes, state.edges, direction: state.direction, groups: groups),
            List.last(statements, header)
          )
        end

      {:ok, _state} ->
        Syntax.error(List.last(statements, header), "unclosed subgraph")

      failure ->
        failure
    end
  end

  defp grouped({"end", _, _}, %{stack: [_ | rest]} = state), do: {:ok, %{state | stack: rest}}
  defp grouped({"end", _, _}, _state), do: :error

  defp grouped({"subgraph " <> rest, _, _}, state) do
    with [_, id, title] <-
           Syntax.match(~r/\A([A-Za-z_][A-Za-z0-9_-]*)(?:\s+\[(.*)\])?\z/s, rest, 2),
         true <- length(state.stack) < 8 and not Enum.any?(state.groups, &(&1.id == id)),
         {:ok, label} <- Syntax.label(if(title == "", do: id, else: title)) do
      group = %{id: id, label: label, parent: List.first(state.stack)}
      {:ok, %{state | groups: state.groups ++ [group], stack: [id | state.stack]}}
    else
      _ -> :error
    end
  end

  defp grouped({"direction " <> direction, _, _}, state) do
    with {:ok, direction} <-
           Map.fetch(
             %{"LR" => :lr, "RL" => :rl, "TB" => :tb, "TD" => :tb, "BT" => :bt},
             direction
           ) do
      case state.stack do
        [] ->
          {:ok, %{state | direction: direction}}

        [id | _] ->
          {:ok,
           %{
             state
             | groups:
                 Enum.map(state.groups, fn g ->
                   if g.id == id, do: Map.put(g, :direction, direction), else: g
                 end)
           }}
      end
    end
  end

  defp grouped({"style " <> rest, _, _}, state) do
    with [_, id, css] <- Regex.run(~r/\A([A-Za-z_][A-Za-z0-9_-]*)\s+(.+)\z/s, rest),
         {:ok, style} <- Styles.css(css, :node) do
      key = if Enum.any?(state.groups, &(&1.id == id)), do: :groups, else: :nodes

      with {:ok, records} <- Style.apply_records(state[key], id, style),
           do: {:ok, Map.put(state, key, records)}
    else
      _ -> :error
    end
  end

  defp grouped({text, _, _}, state) do
    with {:ok, nodes, edges} <- statement(text, state.nodes, state.edges, List.first(state.stack)),
         do: {:ok, %{state | nodes: nodes, edges: edges}}
  end

  defp statement("linkStyle " <> rest, nodes, edges, _group) do
    with [_, index, css] <- Regex.run(~r/\A([0-9]+)\s+(.+)\z/s, rest),
         index = String.to_integer(index),
         true <- index < length(edges),
         {:ok, style} <- Styles.css(css, :edge) do
      {:ok, nodes, List.update_at(edges, index, &Map.merge(&1, style))}
    else
      _ -> :error
    end
  end

  defp statement(text, nodes, edges, group) do
    with {:ok, node, rest, explicit?} <- parse_node(text) do
      node = Map.put(node, :group, group)
      nodes = remember(nodes, node, explicit?)
      chain(node, rest, nodes, edges, group)
    end
  end

  defp chain(_from, "", nodes, edges, _group), do: {:ok, nodes, edges}

  defp chain(from, rest, nodes, edges, group) do
    with {:ok, edge, rest} <- edge(rest),
         {:ok, to, rest, explicit?} <- parse_node(rest) do
      to = Map.put(to, :group, group)
      edge = Map.merge(edge, %{from: from.id, to: to.id})
      chain(to, rest, remember(nodes, to, explicit?), edges ++ [edge], group)
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
         do: {:ok, %{id: id, label: label, shape: shape, declared: true}, rest, true}
  end

  defp shape(id, rest),
    do: {:ok, %{id: id, label: id, shape: :rectangle, declared: false}, rest, false}

  defp remember(nodes, node, false) do
    case Enum.find(nodes, &(&1.id == node.id)) do
      nil ->
        nodes ++ [node]

      %{group: nil} = previous when node.group != nil ->
        Syntax.upsert(nodes, %{previous | group: node.group})

      _previous ->
        nodes
    end
  end

  defp remember(nodes, node, true) do
    previous = Enum.find(nodes, &(&1.id == node.id)) || %{}
    node = Map.put(node, :group, node.group || Map.get(previous, :group))
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
