defmodule Ascii.Mermaid.State do
  @moduledoc false
  alias Ascii.{Diagram, Mermaid.Syntax}

  @spec parse(statements :: [Syntax.position()], header :: Syntax.position()) ::
          {:ok, Diagram.t()} | Ascii.Mermaid.error()
  def parse(statements, header) do
    initial = %{states: [], edges: [], stack: [], direction: :tb}

    result =
      Enum.reduce_while(statements, {:ok, initial}, fn position, {:ok, state} ->
        case statement(position, state) do
          {:ok, state} -> {:cont, {:ok, state}}
          _ -> {:halt, Syntax.error(position, "unsupported or malformed state statement")}
        end
      end)

    case result do
      {:ok, %{stack: []} = state} ->
        Syntax.checked(
          Diagram.state(state.states, state.edges, direction: state.direction),
          List.last(statements, header)
        )

      {:ok, _state} ->
        Syntax.error(List.last(statements, header), "unclosed composite state")

      failure ->
        failure
    end
  end

  defp statement({"}", _, _}, %{stack: [_ | rest]} = state), do: {:ok, %{state | stack: rest}}

  defp statement({"direction " <> rest, _, _}, %{stack: []} = state) do
    with {:ok, direction} <-
           Map.fetch(%{"LR" => :lr, "RL" => :rl, "TB" => :tb, "TD" => :tb, "BT" => :bt}, rest),
         do: {:ok, %{state | direction: direction}}
  end

  defp statement({"state " <> rest, _, _}, state) do
    cond do
      String.ends_with?(rest, "{") ->
        composite(String.trim_trailing(rest, "{") |> String.trim(), state)

      String.ends_with?(rest, "<<choice>>") ->
        id = rest |> String.trim_trailing("<<choice>>") |> String.trim()
        remember(state, id, id, :choice)

      true ->
        with {:ok, id, label} <- declaration(rest), do: remember(state, id, label, :state)
    end
  end

  defp statement({text, _, _}, state) do
    cond do
      String.contains?(text, "-->") ->
        transition(text, state)

      String.contains?(text, ":") ->
        with [id, raw] <- String.split(text, ":", parts: 2),
             {:ok, label} <- Syntax.label(raw),
             do: remember(state, String.trim(id), label, :state)

      true ->
        remember(state, text, text, :state)
    end
  end

  defp composite(rest, state) do
    with true <- length(state.stack) < 8,
         {:ok, id, label} <- declaration(rest),
         {:ok, state} <- remember(state, id, label, :composite),
         true <- not Enum.member?(state.stack, id) do
      {:ok, %{state | stack: [id | state.stack]}}
    else
      _ -> :error
    end
  end

  defp declaration(text) do
    case Regex.run(~r/\A("(?:[^"\\]|\\.)*")\s+as\s+([A-Za-z_][A-Za-z0-9_-]*)\z/s, text) do
      [_, raw, id] -> with {:ok, label} <- Syntax.label(raw), do: {:ok, id, label}
      _ -> with {:ok, id} <- Diagram.Validate.id(text), do: {:ok, id, id}
    end
  end

  defp transition(text, state) do
    with [_, from, to, raw] <-
           Syntax.match(
             ~r/\A(\[\*\]|[A-Za-z_][A-Za-z0-9_-]*?)\s*-->\s*(\[\*\]|[A-Za-z_][A-Za-z0-9_-]*)(?:\s*:\s*(.*))?\z/s,
             text,
             3
           ),
         {:ok, label} <- Syntax.label(raw),
         {:ok, from, state} <- endpoint(from, :initial, state),
         {:ok, to, state} <- endpoint(to, :final, state) do
      {:ok, %{state | edges: state.edges ++ [%{from: from, to: to, label: label}]}}
    else
      _ -> :error
    end
  end

  defp endpoint("[*]", kind, state) do
    existing =
      Enum.find(state.states, &(&1.kind == kind and &1.parent == List.first(state.stack)))

    if existing do
      {:ok, existing.id, state}
    else
      id = fresh(state.states, "state-#{kind}", 1)
      with {:ok, state} <- remember(state, id, "", kind), do: {:ok, id, state}
    end
  end

  defp endpoint(id, _kind, state) do
    if Enum.any?(state.states, &(&1.id == id)) do
      {:ok, id, state}
    else
      with {:ok, state} <- remember(state, id, id, :state), do: {:ok, id, state}
    end
  end

  defp fresh(states, prefix, n) do
    id = "#{prefix}-#{n}"
    if Enum.any?(states, &(&1.id == id)), do: fresh(states, prefix, n + 1), else: id
  end

  defp remember(state, id, label, kind) do
    parent = List.first(state.stack)
    previous = Enum.find(state.states, &(&1.id == id))

    with {:ok, _} <- Diagram.Validate.id(id),
         true <-
           previous == nil or (previous.parent == parent and previous.kind in [:state, kind]),
         {:ok, label} <- Diagram.Validate.text(label) do
      record = %{id: id, label: label, kind: kind, parent: parent}
      {:ok, %{state | states: Syntax.upsert(state.states, record)}}
    else
      _ -> :error
    end
  end
end
