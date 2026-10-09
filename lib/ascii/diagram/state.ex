defmodule Ascii.Diagram.State do
  @moduledoc false
  alias Ascii.Diagram.{Drawing, Graph, Layout, Style, Validate}

  @spec cast(states :: term(), edges :: term(), opts :: term()) ::
          {:ok, map()} | Ascii.Diagram.error()
  def cast(states, edges, opts) do
    with {:ok, direction} <- Validate.direction(opts),
         {:ok, states} <- Validate.records(states, 64, &state/2, :states),
         :ok <- hierarchy(states),
         {:ok, edges} <- Validate.edges(edges, states),
         :ok <- transitions(states, edges) do
      {:ok, %{states: states, edges: edges, direction: direction}}
    end
  end

  defp state(value, _index) do
    with :ok <-
           Validate.keys(value, [:id, :label, :kind, :parent] ++ Style.fields()),
         {:ok, id} <- Validate.id(Map.get(value, :id)),
         {:ok, label} <- Validate.text(Map.get(value, :label, id)),
         {:ok, kind} <-
           Validate.choice(
             Map.get(value, :kind, :state),
             [:state, :initial, :final, :choice, :composite],
             :kind
           ),
         do:
           Validate.styled(
             %{id: id, label: label, kind: kind, parent: Map.get(value, :parent)},
             value
           )
  end

  defp hierarchy(states) do
    composites = Enum.filter(states, &(&1.kind == :composite))
    known = MapSet.new(composites, & &1.id)

    with true <- length(composites) <= 16,
         true <- Enum.all?(states, &(&1.parent == nil or MapSet.member?(known, &1.parent))),
         :ok <- Validate.parents(composites) do
      :ok
    else
      _ -> Validate.error(:state_parent)
    end
  end

  defp transitions(states, edges) do
    known = Map.new(states, &{&1.id, &1})

    valid? =
      Enum.all?(edges, fn edge ->
        from = known[edge.from]
        to = known[edge.to]

        from.kind != :final and to.kind != :initial and
          (from.parent == to.parent or from.kind == :composite or to.kind == :composite)
      end)

    if valid?, do: :ok, else: Validate.error(:state_transition)
  end

  @spec layout(data :: map(), opts :: keyword()) :: Layout.t() | Ascii.Diagram.error()
  def layout(data, opts) do
    {groups, states} = Enum.split_with(data.states, &(&1.kind == :composite))

    nodes =
      Enum.map(states, fn state ->
        shape =
          case state.kind do
            :choice -> :diamond
            :initial -> :initial
            :final -> :final
            _ -> :rounded
          end

        state |> Map.merge(%{group: state.parent, shape: shape}) |> Drawing.node(opts)
      end)

    Graph.layout(
      nodes,
      data.edges,
      groups,
      data.direction,
      opts,
      "state diagram: #{length(data.states)} states, #{length(data.edges)} transitions"
    )
  end
end
