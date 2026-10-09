defmodule Ascii.Diagram.LayoutStyle do
  @moduledoc false
  alias Ascii.Diagram.Style

  @collections %{
    node: :nodes,
    boundary: :boundaries,
    fragment: :fragments,
    note: :notes,
    activation: :activations
  }

  @spec put(
          layout :: Ascii.Diagram.Layout.t(),
          target :: Ascii.Diagram.Layout.target(),
          style :: map()
        ) :: {:ok, Ascii.Diagram.Layout.t()} | Ascii.Diagram.error()
  def put(layout, {:attribute, id, name}, style) do
    with {:ok, node} <- Map.fetch(layout.nodes, id),
         {:ok, attributes} <- Style.apply_records(Map.get(node, :attributes, []), name, style) do
      node = %{node | attributes: attributes}

      commands =
        Enum.map(layout.commands, fn
          {:box, %{id: ^id}, :node} -> {:box, node, :node}
          other -> other
        end)

      {:ok, %{layout | nodes: Map.put(layout.nodes, id, node), commands: commands}}
    else
      _ -> missing({id, name})
    end
  end

  def put(layout, {:edge, id} = target, style) do
    with {:ok, edges} <- Style.apply_records(layout.edges, id, style) do
      record = Enum.find(edges, &(&1.id == id))
      commands = Enum.map(layout.commands, &command(&1, target, record))
      {:ok, %{layout | edges: edges, commands: commands}}
    end
  end

  def put(layout, {kind, id} = target, style) do
    with {:ok, key} <- Map.fetch(@collections, kind),
         {:ok, record} <- Map.fetch(Map.fetch!(layout, key), id) do
      record = Map.merge(record, style)
      commands = Enum.map(layout.commands, &command(&1, target, record))

      {:ok,
       layout
       |> Map.put(key, Map.put(Map.fetch!(layout, key), id, record))
       |> Map.put(:commands, commands)}
    else
      _ -> missing(id)
    end
  end

  def put(_layout, target, _style), do: missing(target)

  defp command({:box, %{id: id}, role}, {role, id}, record), do: {:box, record, role}

  defp command({kind, %{id: id}}, {kind, id}, record)
       when kind in [:boundary, :fragment, :activation], do: {kind, record}

  defp command({:path, %{id: id}}, {:edge, id}, record), do: {:path, record}
  defp command({:edge_label, %{id: id}}, {:edge, id}, record), do: {:edge_label, record}

  defp command({:divider, x, x2, y, label, %{id: id}}, {:fragment, id}, record),
    do: {:divider, x, x2, y, label, record}

  defp command({:lifeline, id, x, y, y2, _ink}, {:node, id}, record),
    do: {:lifeline, id, x, y, y2, Style.ink(record, :lifeline)}

  defp command(command, _target, _record), do: command
  defp missing(id), do: {:error, {:invalid_diagram, {:style_target, id}}}
end
