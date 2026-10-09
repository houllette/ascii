defmodule Ascii.Diagram.Style do
  @moduledoc false
  alias Ascii.Ink

  @fields [:color, :label_color, :border_color, :line_color]

  @spec fields() :: [atom()]
  def fields, do: @fields

  @spec cast(style :: term()) :: {:ok, map()} | Ascii.Diagram.error()
  def cast(style) when is_list(style) do
    if Keyword.keyword?(style), do: cast(Map.new(style)), else: invalid()
  end

  def cast(style) when is_map(style) do
    Enum.reduce_while(style, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      if key in @fields and (value == nil or Ink.color(value) != nil),
        do: {:cont, {:ok, Map.put(acc, key, Ink.color(value))}},
        else: {:halt, invalid()}
    end)
  end

  def cast(_style), do: invalid()

  @spec record(record :: map()) :: {:ok, map()} | Ascii.Diagram.error()
  def record(record), do: record |> Map.take(@fields) |> cast()

  @spec ink(record :: map(), role :: atom()) :: String.t() | nil
  def ink(record, role) when role in [:label, :edge_label],
    do: Map.get(record, :label_color) || Map.get(record, :color)

  def ink(record, role) when role in [:node, :boundary, :fragment, :note],
    do: Map.get(record, :border_color) || Map.get(record, :color)

  def ink(record, _role), do: Map.get(record, :line_color) || Map.get(record, :color)

  @spec apply_records(records :: [map()], id :: String.t(), style :: map()) ::
          {:ok, [map()]} | Ascii.Diagram.error()
  def apply_records(records, id, style) do
    if Enum.any?(records, &(&1.id == id)),
      do: {:ok, Enum.map(records, fn r -> if r.id == id, do: Map.merge(r, style), else: r end)},
      else: {:error, {:invalid_diagram, {:style_target, id}}}
  end

  @spec update(diagram :: Ascii.Diagram.t(), kind :: atom(), id :: String.t(), style :: map()) ::
          {:ok, Ascii.Diagram.t()} | Ascii.Diagram.error()
  def update(%{type: type, data: data} = diagram, :node, id, style) do
    key = node_key(type)

    with {:ok, records} <- apply_records(data[key], id, style),
         do: {:ok, %{diagram | data: Map.put(data, key, records)}}
  end

  def update(%{type: :sequence, data: data} = diagram, kind, id, style)
      when kind in [:edge, :fragment, :note, :activation] do
    {events, found?} = update_events(data.messages, kind, id, style)
    if found?, do: {:ok, %{diagram | data: %{data | messages: events}}}, else: missing(id)
  end

  def update(%{type: type, data: data} = diagram, :edge, id, style)
      when type in [:flowchart, :c4] do
    with {:ok, records} <- apply_records(data.edges, id, style),
         do: {:ok, %{diagram | data: %{data | edges: records}}}
  end

  def update(%{type: :c4, data: data} = diagram, :boundary, id, style) do
    with {:ok, records} <- apply_records(data.boundaries, id, style),
         do: {:ok, %{diagram | data: %{data | boundaries: records}}}
  end

  def update(_diagram, _kind, id, _style), do: missing(id)

  defp node_key(:flowchart), do: :nodes
  defp node_key(:sequence), do: :participants
  defp node_key(:c4), do: :elements

  defp update_events(events, kind, id, style) do
    Enum.map_reduce(events, false, fn event, found? ->
      match? = event.id == id and target_kind(event) == kind
      event = if match?, do: Map.merge(event, style), else: event
      {event, child?} = update_children(event, kind, id, style)
      {event, found? or match? or child?}
    end)
  end

  defp update_children(%{events: events, branches: branches} = event, kind, id, style) do
    {events, found?} = update_events(events, kind, id, style)

    {branches, branch?} =
      Enum.map_reduce(branches, false, fn branch, acc ->
        {events, found?} = update_events(branch.events, kind, id, style)
        {%{branch | events: events}, acc or found?}
      end)

    {%{event | events: events, branches: branches}, found? or branch?}
  end

  defp update_children(event, _kind, _id, _style), do: {event, false}
  defp target_kind(%{from: _}), do: :edge
  defp target_kind(%{kind: :activate}), do: :activation
  defp target_kind(%{kind: :note}), do: :note
  defp target_kind(%{events: _}), do: :fragment
  defp target_kind(_event), do: nil
  defp missing(id), do: {:error, {:invalid_diagram, {:style_target, id}}}

  defp invalid, do: {:error, {:invalid_diagram, :color}}
end
