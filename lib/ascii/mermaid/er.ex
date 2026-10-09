defmodule Ascii.Mermaid.ER do
  @moduledoc false
  alias Ascii.{Diagram, Mermaid.Syntax}
  alias Ascii.Diagram.Style
  alias Ascii.Mermaid.Styles

  @left %{"||" => :one, "|o" => :zero_or_one, "}|" => :one_or_more, "}o" => :zero_or_more}
  @right %{"||" => :one, "o|" => :zero_or_one, "|{" => :one_or_more, "o{" => :zero_or_more}

  @spec parse(statements :: [Syntax.position()], header :: Syntax.position()) ::
          {:ok, Diagram.t()} | Ascii.Mermaid.error()
  def parse(statements, header) do
    initial = %{entities: [], edges: [], current: nil, direction: :tb}

    result =
      Enum.reduce_while(statements, {:ok, initial}, fn position, {:ok, state} ->
        case statement(position, state) do
          {:ok, state} -> {:cont, {:ok, state}}
          _ -> {:halt, Syntax.error(position, "unsupported or malformed ER statement")}
        end
      end)

    case result do
      {:ok, %{current: nil} = state} ->
        Syntax.checked(
          Diagram.er(state.entities, state.edges, direction: state.direction),
          List.last(statements, header)
        )

      {:ok, _state} ->
        Syntax.error(List.last(statements, header), "unclosed entity attributes")

      failure ->
        failure
    end
  end

  defp statement({"}", _, _}, %{current: id} = state) when id != nil,
    do: {:ok, %{state | current: nil}}

  defp statement({text, _, _}, %{current: id} = state) when id != nil do
    with [_, type, name, keys, raw] <-
           Syntax.match(
             ~r/\A([A-Za-z][A-Za-z0-9_?\[\]()-]*)\s+([A-Za-z_][A-Za-z0-9_-]*)(?:\s+((?:PK|FK|UK)(?:\s*,\s*(?:PK|FK|UK))*))?(?:\s+("(?:[^"\\]|\\.)*"))?\z/s,
             text,
             4
           ),
         {:ok, comment} <- Syntax.label(raw) do
      keys =
        if keys == "",
          do: [],
          else:
            keys
            |> String.split(",")
            |> Enum.map(&Map.fetch!(%{"PK" => :pk, "FK" => :fk, "UK" => :uk}, String.trim(&1)))

      attribute = %{name: name, type: type, keys: keys, comment: comment}

      entities =
        Enum.map(state.entities, fn e ->
          if e.id == id, do: %{e | attributes: e.attributes ++ [attribute]}, else: e
        end)

      {:ok, %{state | entities: entities}}
    else
      _ -> :error
    end
  end

  defp statement({"direction " <> rest, _, _}, state) do
    with {:ok, direction} <-
           Map.fetch(%{"LR" => :lr, "RL" => :rl, "TB" => :tb, "BT" => :bt}, rest),
         do: {:ok, %{state | direction: direction}}
  end

  defp statement({"style " <> rest, _, _}, state) do
    with [_, id, css] <- Regex.run(~r/\A([A-Za-z_][A-Za-z0-9_-]*)\s+(.+)\z/s, rest),
         {:ok, style} <- Styles.css(css, :node),
         {:ok, entities} <- Style.apply_records(state.entities, id, style),
         do: {:ok, %{state | entities: entities}}
  end

  defp statement({text, _, _}, state) do
    cond do
      String.ends_with?(text, "{") ->
        with {:ok, id, label} <- entity(String.trim_trailing(text, "{") |> String.trim()),
             {:ok, state} <- remember(state, id, label),
             do: {:ok, %{state | current: id}}

      String.contains?(text, "--") or String.contains?(text, "..") ->
        relationship(text, state)

      true ->
        with {:ok, id, label} <- entity(text), do: remember(state, id, label)
    end
  end

  defp entity(text) do
    with [_, id, raw] <- Syntax.match(~r/\A([A-Za-z_][A-Za-z0-9_-]*)(?:\s*\[(.*)\])?\z/s, text, 2),
         {:ok, label} <- Syntax.label(if(raw == "", do: id, else: raw)),
         do: {:ok, id, label}
  end

  defp remember(state, id, label) do
    previous = Enum.find(state.entities, &(&1.id == id)) || %{id: id, attributes: []}
    label = if label == id and Map.has_key?(previous, :label), do: previous.label, else: label
    {:ok, %{state | entities: Syntax.upsert(state.entities, Map.put(previous, :label, label))}}
  end

  defp relationship(text, state) do
    with [_, from, left, line, right, to, raw] <-
           Regex.run(
             ~r/\A([A-Za-z_][A-Za-z0-9_-]*)\s+(\|\||\|o|\}\||\}o)(--|\.\.)(\|\||o\||\|\{|o\{)\s+([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.+)\z/s,
             text
           ),
         {:ok, label} <- Syntax.label(raw),
         {:ok, state} <- remember(state, from, from),
         {:ok, state} <- remember(state, to, to) do
      edge = %{
        from: from,
        to: to,
        label: label,
        from_cardinality: @left[left],
        to_cardinality: @right[right],
        identifying: line == "--"
      }

      {:ok, %{state | edges: state.edges ++ [edge]}}
    else
      _ -> :error
    end
  end
end
