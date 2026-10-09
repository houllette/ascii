defmodule Ascii.Diagram.SequenceEvents do
  @moduledoc false
  alias Ascii.Diagram.{Style, Text, Validate}

  @fragments [:loop, :alt, :opt, :par, :critical, :break]

  @spec cast(events :: term(), participants :: [map()]) ::
          {:ok, [map()]} | Ascii.Diagram.error()
  def cast(events, participants) do
    context = %{
      participants: participants,
      known: MapSet.new(participants, & &1.id),
      next: 1,
      ids: MapSet.new()
    }

    with {:ok, events, _context} <- events(events, context, 0),
         {:ok, _active} <- balance(events, %{}),
         do: {:ok, events}
  end

  defp events(values, context, depth)
       when is_list(values) and length(values) <= 128 and depth <= 8 do
    Enum.reduce_while(values, {:ok, [], context}, fn value, {:ok, acc, context} ->
      case event(value, context, depth) do
        {:ok, event, context} -> {:cont, {:ok, [event | acc], context}}
        failure -> {:halt, failure}
      end
    end)
    |> then(fn
      {:ok, events, context} -> {:ok, Enum.reverse(events), context}
      failure -> failure
    end)
  end

  defp events(_values, _context, _depth), do: invalid(:events)

  defp event(value, %{next: next} = context, depth) when is_map(value) and next <= 128 do
    kind = Map.get(value, :kind, :message)
    prefix = if kind == :message, do: "message", else: "event"
    id = Map.get(value, :id, "#{prefix}-#{next}")

    if is_binary(id) and id =~ ~r/\A[A-Za-z_][A-Za-z0-9_-]{0,127}\z/ and
         not MapSet.member?(context.ids, id) do
      context = %{context | next: next + 1, ids: MapSet.put(context.ids, id)}
      build(kind, Map.put(value, :id, id), context, depth)
    else
      invalid(:event_id)
    end
  end

  defp event(_value, _context, _depth), do: invalid(:events)

  defp build(:message, value, context, _depth) do
    with {:ok, [message]} <- Validate.edges([Map.delete(value, :kind)], context.participants),
         do: {:ok, message, context}
  end

  defp build(kind, value, context, depth) when kind in @fragments do
    with :ok <- keys(value, [:id, :kind, :label, :events, :branches]),
         {:ok, label} <- Text.cast(Map.get(value, :label, "")),
         {:ok, style} <- Style.record(value),
         {:ok, children, context} <- events(Map.get(value, :events, []), context, depth + 1),
         {:ok, branches, context} <-
           branches(Map.get(value, :branches, []), kind, context, depth + 1) do
      fragment =
        Map.merge(
          %{id: value.id, kind: kind, label: label, events: children, branches: branches},
          style
        )

      {:ok, fragment, context}
    end
  end

  defp build(kind, value, context, _depth) when kind in [:activate, :deactivate] do
    with :ok <- keys(value, [:id, :kind, :participant]),
         true <- MapSet.member?(context.known, Map.get(value, :participant)),
         {:ok, style} <- Style.record(value) do
      {:ok, Map.merge(%{id: value.id, kind: kind, participant: value.participant}, style),
       context}
    else
      false -> invalid(:participant)
      failure -> failure
    end
  end

  defp build(:note, value, context, _depth) do
    with :ok <- keys(value, [:id, :kind, :participants, :label, :position]),
         position = Map.get(value, :position, :over),
         participants = Map.get(value, :participants, []),
         true <- valid_note?(position, participants, context.known),
         {:ok, label} <- Text.cast(Map.get(value, :label, "")),
         {:ok, style} <- Style.record(value) do
      note = %{
        id: value.id,
        kind: :note,
        label: label,
        position: position,
        participants: participants
      }

      {:ok, Map.merge(note, style), context}
    else
      false -> invalid(:note)
      failure -> failure
    end
  end

  defp build(_kind, _value, _context, _depth), do: invalid(:event_kind)

  defp branches(values, kind, context, depth) when is_list(values) and length(values) <= 16 do
    if kind in [:alt, :par, :critical] or values == [] do
      Enum.reduce_while(values, {:ok, [], context}, fn branch, {:ok, acc, context} ->
        case branch(branch, context, depth) do
          {:ok, branch, context} -> {:cont, {:ok, [branch | acc], context}}
          failure -> {:halt, failure}
        end
      end)
      |> then(fn
        {:ok, branches, context} -> {:ok, Enum.reverse(branches), context}
        failure -> failure
      end)
    else
      invalid(:branches)
    end
  end

  defp branches(_values, _kind, _context, _depth), do: invalid(:branches)

  defp branch(value, context, depth) when is_map(value) do
    with true <- Map.keys(value) -- [:label, :events] == [],
         {:ok, label} <- Text.cast(Map.get(value, :label, "")),
         {:ok, children, context} <- events(Map.get(value, :events, []), context, depth) do
      {:ok, %{label: label, events: children}, context}
    else
      false -> invalid(:branch)
      failure -> failure
    end
  end

  defp branch(_value, _context, _depth), do: invalid(:branch)

  defp valid_note?(position, participants, known) when is_list(participants) do
    position in [:left, :right, :over] and length(participants) in 1..2 and
      (position == :over or length(participants) == 1) and
      Enum.all?(participants, &MapSet.member?(known, &1))
  end

  defp valid_note?(_position, _participants, _known), do: false

  defp keys(value, fields) do
    if Map.keys(value) -- (fields ++ Style.fields()) == [], do: :ok, else: invalid(:event_keys)
  end

  defp balance(events, active) do
    Enum.reduce_while(events, {:ok, active}, fn event, {:ok, active} ->
      case transition(event, active) do
        {:ok, active} -> {:cont, {:ok, active}}
        failure -> {:halt, failure}
      end
    end)
  end

  defp transition(%{kind: :activate, participant: id}, active),
    do: {:ok, Map.update(active, id, 1, &(&1 + 1))}

  defp transition(%{kind: :deactivate, participant: id}, active) do
    case Map.get(active, id, 0) do
      0 -> invalid({:deactivate, id})
      1 -> {:ok, Map.delete(active, id)}
      count -> {:ok, Map.put(active, id, count - 1)}
    end
  end

  defp transition(%{events: children, branches: branches}, active) do
    Enum.reduce_while([children | Enum.map(branches, & &1.events)], {:ok, active}, fn events,
                                                                                      {:ok, _} ->
      case balance(events, active) do
        {:ok, ^active} -> {:cont, {:ok, active}}
        {:ok, _changed} -> {:halt, invalid(:fragment_activation)}
        failure -> {:halt, failure}
      end
    end)
  end

  defp transition(_event, active), do: {:ok, active}
  defp invalid(field), do: {:error, {:invalid_diagram, field}}
end
