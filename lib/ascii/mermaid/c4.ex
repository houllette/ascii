defmodule Ascii.Mermaid.C4 do
  @moduledoc false
  alias Ascii.{Diagram, Mermaid.Syntax}
  alias Ascii.Diagram.Style
  alias Ascii.Mermaid.Styles

  @kinds %{
    "Person" => :person,
    "System" => :system,
    "SystemDb" => :database,
    "SystemQueue" => :queue,
    "Container" => :container,
    "ContainerDb" => :database,
    "ContainerQueue" => :queue,
    "Component" => :component,
    "ComponentDb" => :database,
    "ComponentQueue" => :queue
  }
  @boundaries ~w(Boundary Enterprise_Boundary System_Boundary Container_Boundary)

  @spec parse(statements :: [Syntax.position()], level :: atom(), header :: Syntax.position()) ::
          {:ok, Diagram.t()} | Ascii.Mermaid.error()
  def parse(statements, level, header) do
    initial = %{elements: [], edges: [], boundaries: [], boundary: []}

    result =
      Enum.reduce_while(statements, {:ok, initial}, fn position, {:ok, state} ->
        case statement(position, state) do
          {:ok, state} -> {:cont, {:ok, state}}
          failure -> {:halt, failure}
        end
      end)

    case result do
      {:ok, %{boundary: []} = state} ->
        Syntax.checked(
          Diagram.c4(level, state.elements, state.edges, boundaries: state.boundaries),
          List.last(statements, header)
        )

      {:ok, _state} ->
        Syntax.error(List.last(statements, header), "unclosed boundary")

      failure ->
        failure
    end
  end

  defp statement({"}", _, _}, %{boundary: [_ | rest]} = state),
    do: {:ok, %{state | boundary: rest}}

  defp statement({text, _, _} = position, state) do
    with [_, name, rest] <- Regex.run(~r/\A([A-Za-z_]+)\((.*)\z/s, text),
         {:ok, raw, rest} <- Syntax.delimited(rest, ?)),
         {:ok, state} <- arguments(name, raw, rest, state) do
      {:ok, state}
    else
      _ -> Syntax.error(position, "unsupported or malformed C4 statement")
    end
  end

  defp arguments("UpdateElementStyle", raw, "", state) do
    with {:ok, [id], style} <- Styles.named(raw, :node),
         do: element_style(state, id, style)
  end

  defp arguments("UpdateRelStyle", raw, "", state) do
    with {:ok, [from, to], style} <- Styles.named(raw, :edge),
         true <- Enum.any?(state.edges, &(&1.from == from and &1.to == to)) do
      edges =
        Enum.map(state.edges, fn edge ->
          if edge.from == from and edge.to == to, do: Map.merge(edge, style), else: edge
        end)

      {:ok, %{state | edges: edges}}
    else
      _ -> :error
    end
  end

  defp arguments(name, raw, rest, state) do
    with {:ok, args} <- Syntax.arguments(raw), do: call(name, args, rest, state)
  end

  defp element_style(state, id, style) do
    key = if Enum.any?(state.elements, &(&1.id == id)), do: :elements, else: :boundaries

    with {:ok, records} <- Style.apply_records(state[key], id, style),
         do: {:ok, Map.put(state, key, records)}
  end

  defp call(name, [id, label], "{", state) when name in @boundaries do
    boundary = %{id: id, label: label, parent: List.first(state.boundary)}
    {:ok, %{state | boundary: [id | state.boundary], boundaries: state.boundaries ++ [boundary]}}
  end

  defp call("Rel", [from, to, label], "", state),
    do: {:ok, %{state | edges: state.edges ++ [%{from: from, to: to, label: label}]}}

  defp call("Rel", [from, to, label, technology], "", state),
    do: call("Rel", [from, to, label <> " [" <> technology <> "]"], "", state)

  defp call(name, args, "", state) do
    base = String.replace_suffix(name, "_Ext", "")

    with {:ok, kind} <- Map.fetch(@kinds, base),
         {:ok, element} <- element(base, kind, args) do
      element =
        Map.merge(element, %{external: base != name, boundary: List.first(state.boundary)})

      {:ok, %{state | elements: state.elements ++ [element]}}
    else
      _ -> :error
    end
  end

  defp call(_name, _args, _rest, _state), do: :error

  defp element(name, kind, [id, label | rest]) do
    if String.starts_with?(name, "Container") or String.starts_with?(name, "Component") do
      case rest do
        [technology] ->
          {:ok, %{id: id, label: label, kind: kind, technology: technology}}

        [technology, description] ->
          {:ok,
           %{id: id, label: label, kind: kind, technology: technology, description: description}}

        _ ->
          :error
      end
    else
      case rest do
        [] -> {:ok, %{id: id, label: label, kind: kind}}
        [description] -> {:ok, %{id: id, label: label, kind: kind, description: description}}
        _ -> :error
      end
    end
  end

  defp element(_name, _kind, _args), do: :error
end
