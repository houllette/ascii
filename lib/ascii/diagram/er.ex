defmodule Ascii.Diagram.ER do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Graph, Layout, Style, Text, Validate}

  @spec cast(entities :: term(), edges :: term(), opts :: term()) ::
          {:ok, map()} | Ascii.Diagram.error()
  def cast(entities, edges, opts) do
    with {:ok, direction} <- Validate.direction(opts),
         {:ok, entities} <- Validate.records(entities, 64, &entity/2, :entities),
         true <- Enum.sum(Enum.map(entities, &length(&1.attributes))) <= 512,
         {:ok, edges} <- relationships(edges, entities) do
      {:ok, %{entities: entities, edges: edges, direction: direction}}
    else
      false -> Validate.error(:attributes_size)
      failure -> failure
    end
  end

  defp entity(value, _index) do
    with :ok <- Validate.keys(value, [:id, :label, :attributes] ++ Style.fields()),
         {:ok, id} <- Validate.id(Map.get(value, :id)),
         {:ok, label} <- Validate.text(Map.get(value, :label, id)),
         {:ok, attributes} <-
           Validate.records(Map.get(value, :attributes, []), 64, &attribute/2, :attributes, true),
         do: Validate.styled(%{id: id, label: label, attributes: attributes}, value)
  end

  defp attribute(value, _index) do
    with :ok <- Validate.keys(value, [:name, :type, :keys, :comment] ++ Style.fields()),
         {:ok, name} <- short_text(Map.get(value, :name)),
         {:ok, type} <- short_text(Map.get(value, :type, ""), true),
         {:ok, comment} <- Validate.text(Map.get(value, :comment, "")),
         keys = Map.get(value, :keys, []),
         true <-
           is_list(keys) and length(keys) <= 3 and Enum.all?(keys, &(&1 in [:pk, :fk, :uk])) and
             Enum.uniq(keys) == keys do
      Validate.styled(%{id: name, name: name, type: type, keys: keys, comment: comment}, value)
    else
      false -> Validate.error(:attribute_keys)
      failure -> failure
    end
  end

  defp short_text(value, empty? \\ false) do
    with {:ok, text} <- Validate.text(value),
         true <-
           byte_size(text) <= 128 and not String.contains?(text, "\n") and (empty? or text != "") do
      {:ok, text}
    else
      _ -> Validate.error(:attribute_text)
    end
  end

  defp relationships(edges, entities) do
    with {:ok, records} <- Validate.records(edges, 128, &relationship/2, :edges, true),
         {:ok, _} <-
           Validate.edges(
             Enum.map(records, &Map.drop(&1, [:from_cardinality, :to_cardinality, :identifying])),
             entities
           ),
         do: {:ok, records}
  end

  defp relationship(value, index) do
    with :ok <-
           Validate.keys(
             value,
             [:id, :from, :to, :label, :from_cardinality, :to_cardinality, :identifying] ++
               Style.fields()
           ),
         {:ok, id} <- Validate.id(Map.get(value, :id, "edge-#{index}")),
         {:ok, label} <- Validate.text(Map.get(value, :label, "")),
         {:ok, from} <- cardinality(Map.get(value, :from_cardinality, :one)),
         {:ok, to} <- cardinality(Map.get(value, :to_cardinality, :zero_or_more)),
         {:ok, identifying} <-
           Validate.choice(Map.get(value, :identifying, true), [true, false], :identifying) do
      Validate.styled(
        %{
          id: id,
          from: Map.get(value, :from),
          to: Map.get(value, :to),
          label: label,
          from_cardinality: from,
          to_cardinality: to,
          identifying: identifying,
          style: if(identifying, do: :solid, else: :dashed),
          arrow: false
        },
        value
      )
    end
  end

  defp cardinality(value),
    do: Validate.choice(value, [:one, :zero_or_one, :one_or_more, :zero_or_more], :cardinality)

  @spec attribute_style(entities :: [map()], id :: String.t(), name :: String.t(), style :: map()) ::
          {:ok, [map()]} | Ascii.Diagram.error()
  def attribute_style(entities, id, name, style) do
    case Enum.find(entities, &(&1.id == id)) do
      nil ->
        Validate.error({:style_target, id})

      entity ->
        with {:ok, attributes} <- Style.apply_records(entity.attributes, name, style),
             do:
               {:ok,
                Enum.map(entities, fn e ->
                  if e.id == id, do: %{e | attributes: attributes}, else: e
                end)}
    end
  end

  @spec layout(data :: map(), opts :: keyword()) :: Layout.t() | Ascii.Diagram.error()
  def layout(data, opts) do
    nodes =
      Enum.map(data.entities, fn entity ->
        node = box(entity, opts)
        degree = Enum.count(data.edges, &(&1.from == entity.id or &1.to == entity.id))

        if data.direction in [:lr, :rl],
          do: %{node | height: max(node.height, degree * 2 + 3)},
          else: %{node | width: max(node.width, degree * 2 + 3)}
      end)

    Graph.layout(
      nodes,
      data.edges,
      [],
      data.direction,
      opts,
      "ER diagram: #{length(nodes)} entities, #{length(data.edges)} relationships"
    )
  end

  defp box(entity, opts) do
    headers = Drawing.wrap(entity.label, opts[:label_width])

    {attributes, _row} =
      Enum.map_reduce(entity.attributes, length(headers) + 2, fn attribute, row ->
        keys = Enum.map_join(attribute.keys, ",", &(Atom.to_string(&1) |> String.upcase()))

        label =
          [attribute.type, attribute.name, keys] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")

        lines =
          Drawing.wrap(label, opts[:label_width]) ++
            if(attribute.comment == "",
              do: [],
              else: Drawing.wrap(attribute.comment, opts[:label_width])
            )

        {Map.merge(attribute, %{lines: lines, row: row}), row + length(lines)}
      end)

    lines = headers ++ Enum.flat_map(attributes, & &1.lines)
    width = max(3, Enum.max(Enum.map(lines, &Text.width/1))) + 4
    height = length(lines) + 3 + if(attributes == [], do: 1, else: 0)

    Map.merge(entity, %{
      shape: :entity,
      group: nil,
      width: width,
      height: height,
      lines: lines,
      header_lines: headers,
      attributes: attributes
    })
  end
end
