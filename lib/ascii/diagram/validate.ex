defmodule Ascii.Diagram.Validate do
  @moduledoc false
  alias Ascii.Diagram.{SequenceEvents, Style, Text}

  @type result :: {:ok, term()} | Ascii.Diagram.error()

  @spec direction(opts :: term(), allowed :: [atom()]) :: result()
  def direction(opts, allowed \\ [:direction]) do
    with :ok <- keywords(opts, allowed),
         do: choice(Keyword.get(opts, :direction, :tb), [:tb, :bt, :lr, :rl], :direction)
  end

  @spec level(level :: term()) :: :ok | Ascii.Diagram.error()
  def level(level) when level in [:context, :container, :component], do: :ok
  def level(_level), do: error(:level)

  @spec nodes(nodes :: term(), groups :: [map()]) :: result()
  def nodes(nodes, groups \\ []) do
    known = MapSet.new(groups, & &1.id)

    with {:ok, nodes} <- records(nodes, 64, &node/2, :nodes, groups != []),
         true <- Enum.all?(nodes, &(&1.group == nil or MapSet.member?(known, &1.group))),
         true <- Enum.all?(nodes, &(not MapSet.member?(known, &1.id))) do
      {:ok, nodes}
    else
      false -> error(:group)
      failure -> failure
    end
  end

  defp node(value, _index) do
    with :ok <- keys(value, [:id, :label, :shape, :group] ++ Style.fields()),
         {:ok, id} <- id(Map.get(value, :id)),
         {:ok, label} <- text(Map.get(value, :label, id)),
         {:ok, shape} <-
           choice(Map.get(value, :shape, :rectangle), [:rectangle, :rounded, :diamond], :shape) do
      styled(%{id: id, label: label, shape: shape, group: Map.get(value, :group)}, value)
    end
  end

  @spec groups(opts :: term()) :: result()
  def groups(opts) do
    with :ok <- keywords(opts, [:direction, :groups]),
         {:ok, groups} <- records(Keyword.get(opts, :groups, []), 16, &group/2, :groups, true),
         :ok <- parents(groups),
         do: {:ok, groups}
  end

  defp group(value, index) do
    with :ok <- keys(value, [:id, :label, :parent, :direction] ++ Style.fields()),
         {:ok, direction} <-
           choice(Map.get(value, :direction), [nil, :tb, :bt, :lr, :rl], :direction),
         {:ok, group} <- boundary(Map.delete(value, :direction), index) do
      {:ok, Map.put(group, :direction, direction)}
    end
  end

  @spec participants(participants :: term()) :: result()
  def participants(participants), do: records(participants, 32, &participant/2, :participants)

  defp participant(value, _index) do
    with :ok <- keys(value, [:id, :label, :kind] ++ Style.fields()),
         {:ok, id} <- id(Map.get(value, :id)),
         {:ok, label} <- text(Map.get(value, :label, id)),
         {:ok, kind} <- choice(Map.get(value, :kind, :participant), [:participant, :actor], :kind) do
      styled(%{id: id, label: label, kind: kind}, value)
    end
  end

  @spec boundaries(opts :: term()) :: result()
  def boundaries(opts) do
    with :ok <- keywords(opts, [:boundaries]),
         {:ok, boundaries} <-
           records(Keyword.get(opts, :boundaries, []), 16, &boundary/2, :boundaries, true),
         :ok <- parents(boundaries),
         do: {:ok, boundaries}
  end

  defp boundary(value, _index) do
    with :ok <- keys(value, [:id, :label, :parent] ++ Style.fields()),
         {:ok, id} <- id(Map.get(value, :id)),
         {:ok, label} <- text(Map.get(value, :label, id)) do
      styled(%{id: id, label: label, parent: Map.get(value, :parent)}, value)
    end
  end

  @spec elements(elements :: term(), boundaries :: [map()]) :: result()
  def elements(elements, boundaries) do
    known = MapSet.new(boundaries, & &1.id)

    with {:ok, elements} <-
           records(elements, 64, fn value, _index -> element(value, known) end, :elements),
         true <- Enum.all?(elements, &(not MapSet.member?(known, &1.id))) do
      {:ok, elements}
    else
      false -> error(:boundary_id)
      failure -> failure
    end
  end

  defp element(value, known) do
    with :ok <-
           keys(
             value,
             [:id, :label, :kind, :technology, :description, :external, :boundary] ++
               Style.fields()
           ),
         {:ok, id} <- id(Map.get(value, :id)),
         {:ok, label} <- text(Map.get(value, :label, id)),
         {:ok, kind} <-
           choice(
             Map.get(value, :kind, :system),
             [:person, :system, :container, :component, :database, :queue],
             :kind
           ),
         {:ok, technology} <- text(Map.get(value, :technology, "")),
         {:ok, description} <- text(Map.get(value, :description, "")),
         {:ok, external} <- choice(Map.get(value, :external, false), [true, false], :external),
         {:ok, boundary} <- boundary_id(Map.get(value, :boundary), known) do
      styled(
        %{
          id: id,
          label: label,
          kind: kind,
          technology: technology,
          description: description,
          external: external,
          boundary: boundary
        },
        value
      )
    end
  end

  defp boundary_id(nil, _known), do: {:ok, nil}

  defp boundary_id(id, known) do
    if MapSet.member?(known, id), do: {:ok, id}, else: error({:boundary, id})
  end

  @spec edges(edges :: term(), nodes :: [map()]) :: result()
  def edges(edges, nodes), do: connections(edges, nodes, "edge", :edges)

  @spec messages(messages :: term(), participants :: [map()]) :: result()
  def messages(messages, participants),
    do: SequenceEvents.cast(messages, participants)

  defp connections(values, nodes, prefix, field) do
    known = MapSet.new(nodes, & &1.id)
    records(values, 128, &connection(&1, &2, known, prefix), field, true)
  end

  defp connection(value, index, known, prefix) do
    with :ok <- keys(value, [:id, :from, :to, :label, :style, :arrow] ++ Style.fields()),
         {:ok, id} <- id(Map.get(value, :id, "#{prefix}-#{index}")),
         {:ok, from} <- endpoint(Map.get(value, :from), known),
         {:ok, to} <- endpoint(Map.get(value, :to), known),
         {:ok, label} <- text(Map.get(value, :label, "")),
         {:ok, style} <- choice(Map.get(value, :style, :solid), [:solid, :dashed], :style),
         {:ok, arrow} <- choice(Map.get(value, :arrow, true), [true, false], :arrow) do
      styled(%{id: id, from: from, to: to, label: label, style: style, arrow: arrow}, value)
    end
  end

  defp endpoint(id, known) do
    if MapSet.member?(known, id), do: {:ok, id}, else: error({:endpoint, id})
  end

  @spec records(
          values :: term(),
          limit :: pos_integer(),
          fun :: function(),
          field :: atom(),
          empty? :: boolean()
        ) :: result()
  def records(values, limit, fun, field, empty? \\ false)

  def records(values, limit, fun, field, empty?) when is_list(values) do
    if length(values) <= limit and (empty? or values != []) do
      with {:ok, records} <- cast_records(values, fun),
           true <- records |> Enum.map(& &1.id) |> Enum.uniq() |> length() == length(records) do
        {:ok, records}
      else
        false -> error({field, :duplicate_id})
        failure -> failure
      end
    else
      error({field, :size})
    end
  end

  def records(_values, _limit, _fun, field, _empty?), do: error(field)

  defp cast_records(values, fun) do
    values
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {value, i}, {:ok, acc} ->
      case fun.(value, i) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        failure -> {:halt, failure}
      end
    end)
    |> then(fn
      {:ok, records} -> {:ok, Enum.reverse(records)}
      failure -> failure
    end)
  end

  @spec text(value :: term()) :: result()
  def text(value), do: Text.cast(value)

  @spec styled(record :: map(), given :: map()) :: result()
  def styled(record, given) do
    with {:ok, style} <- Style.record(given), do: {:ok, Map.merge(record, style)}
  end

  @spec parents(boundaries :: [map()]) :: :ok | Ascii.Diagram.error()
  def parents(boundaries) do
    parents = Map.new(boundaries, &{&1.id, &1.parent})

    if Enum.all?(boundaries, &valid_parent?(&1.parent, parents, MapSet.new([&1.id]))),
      do: :ok,
      else: error(:boundary_parent)
  end

  defp valid_parent?(nil, _parents, _seen), do: true

  defp valid_parent?(id, parents, seen) do
    Map.has_key?(parents, id) and not MapSet.member?(seen, id) and
      valid_parent?(parents[id], parents, MapSet.put(seen, id))
  end

  @spec id(value :: term()) :: result()
  def id(value) when is_binary(value) and byte_size(value) in 1..128 do
    if value =~ ~r/\A[A-Za-z_][A-Za-z0-9_-]*\z/, do: {:ok, value}, else: error(:id)
  end

  def id(_value), do: error(:id)

  @spec keys(value :: term(), allowed :: [atom()]) :: :ok | Ascii.Diagram.error()
  def keys(value, allowed) when is_map(value) do
    if Map.keys(value) -- allowed == [], do: :ok, else: error(:keys)
  end

  def keys(_value, _allowed), do: error(:record)

  defp keywords(opts, allowed) when is_list(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [],
      do: :ok,
      else: error(:options)
  end

  defp keywords(_opts, _allowed), do: error(:options)

  @spec choice(value :: term(), allowed :: [term()], field :: atom()) :: result()
  def choice(value, allowed, field) do
    if value in allowed, do: {:ok, value}, else: error(field)
  end

  @spec error(field :: term()) :: Ascii.Diagram.error()
  def error(field), do: {:error, {:invalid_diagram, field}}
end
