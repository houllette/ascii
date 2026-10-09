defmodule Ascii.Mermaid.Sequence do
  @moduledoc false
  alias Ascii.{Diagram, Mermaid.Syntax}

  @fragments %{
    "loop" => :loop,
    "alt" => :alt,
    "opt" => :opt,
    "par" => :par,
    "critical" => :critical,
    "break" => :break
  }

  @spec parse(statements :: [Syntax.position()], header :: Syntax.position()) ::
          {:ok, Diagram.t()} | Ascii.Mermaid.error()
  def parse(statements, header) do
    state = %{participants: [], active: %{}}

    with {:ok, events, state, [], :eof} <- block(statements, state, nil, header, 0) do
      Syntax.checked(Diagram.sequence(state.participants, events), List.last(statements, header))
    end
  end

  defp block(statements, state, kind, opening, depth),
    do: items(statements, state, kind, opening, depth, [])

  defp items([], state, nil, _opening, _depth, acc), do: {:ok, Enum.reverse(acc), state, [], :eof}

  defp items([], _state, _kind, opening, _depth, _acc),
    do: Syntax.error(opening, "unclosed sequence fragment")

  defp items([{text, _, _} = position | rest], state, kind, opening, depth, acc) do
    cond do
      text == "end" and kind != nil -> {:ok, Enum.reverse(acc), state, rest, {:end, position}}
      text == "end" -> Syntax.error(position, "unexpected end")
      separator?(text) -> separator(text, position, rest, state, kind, acc)
      true -> item(text, position, rest, state, kind, opening, depth, acc)
    end
  end

  defp item(text, position, rest, state, kind, opening, depth, acc) do
    case fragment_head(text) do
      {:ok, fragment_kind, label} ->
        with true <- depth < 8,
             {:ok, fragment, state, rest} <-
               fragment(rest, state, fragment_kind, label, position, depth + 1) do
          items(rest, state, kind, opening, depth, [fragment | acc])
        else
          false -> Syntax.error(position, "sequence fragments exceed eight levels")
          failure -> failure
        end

      :error ->
        case statement(text, state, position) do
          {:ok, events, state} ->
            items(rest, state, kind, opening, depth, Enum.reverse(events) ++ acc)

          failure ->
            failure
        end
    end
  end

  defp fragment_head(text) do
    case Regex.run(~r/\A(loop|alt|opt|par|critical|break)(?:\s+(.*))?\z/s, text) do
      [_, kind] -> {:ok, @fragments[kind], ""}
      [_, kind, label] -> {:ok, @fragments[kind], label}
      _ -> :error
    end
  end

  defp fragment(rest, state, kind, label, position, depth) do
    active = state.active

    with {:ok, events, state, rest, stop} <- block(rest, state, kind, position, depth),
         {:ok, branches, state, rest} <-
           branch_blocks(stop, rest, state, kind, position, depth, active, []) do
      {:ok, %{kind: kind, label: label, events: events, branches: branches}, state, rest}
    end
  end

  defp branch_blocks({:end, position}, rest, state, _kind, _opening, _depth, active, branches) do
    if state.active == active,
      do: {:ok, Enum.reverse(branches), state, rest},
      else: Syntax.error(position, "activations must balance within each fragment branch")
  end

  defp branch_blocks(
         {:branch, label, position},
         rest,
         state,
         kind,
         opening,
         depth,
         active,
         branches
       ) do
    if state.active == active do
      with {:ok, events, state, rest, stop} <- block(rest, state, kind, opening, depth) do
        branch_blocks(stop, rest, state, kind, opening, depth, active, [
          %{label: label, events: events} | branches
        ])
      end
    else
      Syntax.error(position, "activations must balance within each fragment branch")
    end
  end

  defp separator?(text), do: Regex.match?(~r/\A(?:else|and|option)(?:\s|\z)/, text)

  defp separator(text, position, rest, state, kind, acc) do
    [_, word | label] = Regex.run(~r/\A(else|and|option)(?:\s+(.*))?\z/s, text)

    if {kind, word} in [{:alt, "else"}, {:par, "and"}, {:critical, "option"}],
      do: {:ok, Enum.reverse(acc), state, rest, {:branch, Enum.join(label), position}},
      else: Syntax.error(position, "unexpected fragment branch")
  end

  defp statement(text, state, position) do
    case Regex.run(
           ~r/\A(participant|actor)\s+([A-Za-z_][A-Za-z0-9_-]*)(?:\s+as\s+(.+))?\z/s,
           text
         ) do
      [_, kind, id] ->
        {:ok, [],
         %{state | participants: Syntax.upsert(state.participants, participant(id, id, kind))}}

      [_, kind, id, label] ->
        {:ok, [],
         %{state | participants: Syntax.upsert(state.participants, participant(id, label, kind))}}

      _ ->
        activity(text, state, position)
    end
  end

  defp activity(text, state, position) do
    case Regex.run(~r/\A(activate|deactivate)\s+([A-Za-z_][A-Za-z0-9_-]*)\z/, text) do
      [_, kind, id] -> activate(state, kind, id, position)
      _ -> note(text, state, position)
    end
  end

  defp activate(state, "activate", id, _position) do
    state = ensure_participants(state, [id])

    {:ok, [%{kind: :activate, participant: id}],
     %{state | active: Map.update(state.active, id, 1, &(&1 + 1))}}
  end

  defp activate(state, "deactivate", id, position) do
    case Map.get(state.active, id, 0) do
      0 ->
        Syntax.error(position, "deactivate without an activation")

      1 ->
        {:ok, [%{kind: :deactivate, participant: id}],
         %{state | active: Map.delete(state.active, id)}}

      count ->
        {:ok, [%{kind: :deactivate, participant: id}],
         %{state | active: Map.put(state.active, id, count - 1)}}
    end
  end

  defp note(text, state, position) do
    case Regex.run(
           ~r/\ANote\s+(left of|right of|over)\s+([A-Za-z_][A-Za-z0-9_-]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_-]*)?)\s*:\s*(.*)\z/s,
           text
         ) do
      [_, location, ids, label] ->
        ids = ids |> String.split(",") |> Enum.map(&String.trim/1)

        location =
          case location do
            "left of" -> :left
            "right of" -> :right
            "over" -> :over
          end

        {:ok, [%{kind: :note, participants: ids, position: location, label: label}],
         ensure_participants(state, ids)}

      _ ->
        message(text, state, position)
    end
  end

  defp message(text, state, position) do
    case Regex.run(
           ~r/\A([A-Za-z_][A-Za-z0-9_-]*?)\s*(-->>|->>|-->|->)([+-]?)\s*([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)\z/s,
           text
         ) do
      [_, from, arrow, flag, to, label] ->
        state = ensure_participants(state, [from, to])

        message = %{
          from: from,
          to: to,
          label: label,
          style: if(String.starts_with?(arrow, "--"), do: :dashed, else: :solid),
          arrow: String.ends_with?(arrow, ">>")
        }

        with {:ok, activity, state} <- arrow_activity(flag, from, to, state, position),
             do: {:ok, [message | activity], state}

      _ ->
        Syntax.error(position, "unsupported or malformed sequence statement")
    end
  end

  defp arrow_activity("", _from, _to, state, _position), do: {:ok, [], state}

  defp arrow_activity("+", _from, to, state, position),
    do: activate(state, "activate", to, position)

  defp arrow_activity("-", from, _to, state, position),
    do: activate(state, "deactivate", from, position)

  defp ensure_participants(state, ids) do
    participants =
      Enum.reduce(ids, state.participants, fn id, acc ->
        if Enum.any?(acc, &(&1.id == id)),
          do: acc,
          else: acc ++ [participant(id, id, "participant")]
      end)

    %{state | participants: participants}
  end

  defp participant(id, label, "actor"), do: %{id: id, label: label, kind: :actor}
  defp participant(id, label, _kind), do: %{id: id, label: label, kind: :participant}
end
