defmodule Ascii.Diagram do
  @moduledoc """
  Native, data-driven diagrams rendered as `Ascii.Frame`s.

  Flowcharts, sequences, C4 views, states and ER diagrams have separate models and layout
  strategies. They share drawing and the existing frame renderers; no Node,
  browser or dependency is required. See the [diagram guide](guides/diagrams.md)
  for the supported Mermaid syntax and limits.

      iex> {:ok, diagram} = Ascii.Diagram.flowchart([%{id: "a", label: "Hello"}], [])
      iex> {:ok, frame} = Ascii.Diagram.render(diagram)
      iex> frame.text =~ "Hello"
      true

  Constructors validate data without truncation. Labels accept single-cell
  Unicode and newlines, normalized to NFC. Wide characters, emoji and
  residual combining marks require a different display-width contract and
  are rejected. The drawing itself can use ASCII or Unicode.
  """

  alias Ascii.Diagram.{C4, ER, Flowchart, Layout, Options, Sequence, State, Style, Validate}

  @type t :: %__MODULE__{type: :flowchart | :sequence | :c4 | :state | :er, data: map()}
  @type error ::
          {:error, {:invalid_diagram, term()}}
          | {:error, {:invalid_option, term()}}
          | {:error, {:too_large, {pos_integer(), pos_integer()}}}
          | {:error, {:too_many_colors, pos_integer()}}

  @enforce_keys [:type, :data]
  defstruct [:type, :data]

  @doc """
  A directed graph with optional nested groups. IDs are strings and direction
  defaults to `:tb`. Nodes take `group:`; `groups:` definitions take `id`,
  `label`, `parent` and optional local `direction`. Edges may end at groups.
  """
  @spec flowchart(nodes :: [map()], edges :: [map()], opts :: keyword()) :: {:ok, t()} | error()
  def flowchart(nodes, edges, opts \\ []) do
    with {:ok, direction} <- Validate.direction(opts, [:direction, :groups]),
         {:ok, groups} <- Validate.groups(opts),
         {:ok, nodes} <- Validate.nodes(nodes, groups),
         {:ok, edges} <- Validate.edges(edges, nodes ++ groups) do
      {:ok,
       %__MODULE__{
         type: :flowchart,
         data: %{nodes: nodes, edges: edges, direction: direction, groups: groups}
       }}
    end
  end

  @doc """
  States and labelled transitions, with `:state`, `:initial`, `:final`,
  `:choice` and `:composite` kinds. `parent:` names a composite state.
  Initial states have no incoming transitions; final states have no outgoing
  transitions. `direction:` defaults to `:tb`. This describes a diagram;
  it does not execute a state machine.
  """
  @spec state(states :: [map()], transitions :: [map()], opts :: keyword()) ::
          {:ok, t()} | error()
  def state(states, transitions, opts \\ []) do
    with {:ok, data} <- State.cast(states, transitions, opts),
         do: {:ok, %__MODULE__{type: :state, data: data}}
  end

  @doc """
  Entities with attribute compartments and cardinality at both relationship
  ends. Attributes take `:name`, `:type`, `:keys` (`:pk`, `:fk`, `:uk`) and
  `:comment`. Cardinalities are `:one`, `:zero_or_one`, `:one_or_more`,
  `:zero_or_more`. `identifying: false` draws a dashed relationship.
  Optional foreground styles work on entities, attributes and relationships.
  """
  @spec er(entities :: [map()], relationships :: [map()], opts :: keyword()) ::
          {:ok, t()} | error()
  def er(entities, relationships, opts \\ []) do
    with {:ok, data} <- ER.cast(entities, relationships, opts),
         do: {:ok, %__MODULE__{type: :er, data: data}}
  end

  @doc "Participants in display order and ordered events: messages, notes, activations and nested fragments."
  @spec sequence(participants :: [map()], messages :: [map()]) :: {:ok, t()} | error()
  def sequence(participants, messages) do
    with {:ok, participants} <- Validate.participants(participants),
         {:ok, messages} <- Validate.messages(messages, participants) do
      {:ok, %__MODULE__{type: :sequence, data: %{participants: participants, messages: messages}}}
    end
  end

  @doc """
  A C4 `:context`, `:container` or `:component` view.

  Elements take `:kind`, `:technology`, `:description`, `:external` and an
  optional `:boundary` ID. `boundaries:` is a list of `%{id:, label:}` maps,
  with `parent:` for nested boundaries. Elements and boundaries can carry
  optional foreground styles (`:color`, `:label_color`, `:border_color`).
  """
  @spec c4(level :: atom(), elements :: [map()], relationships :: [map()], opts :: keyword()) ::
          {:ok, t()} | error()
  def c4(level, elements, relationships, opts \\ []) do
    with :ok <- Validate.level(level),
         {:ok, boundaries} <- Validate.boundaries(opts),
         {:ok, elements} <- Validate.elements(elements, boundaries),
         {:ok, edges} <- Validate.edges(relationships, elements) do
      data = %{level: level, elements: elements, edges: edges, boundaries: boundaries}
      {:ok, %__MODULE__{type: :c4, data: data}}
    end
  end

  @doc """
  Computes deterministic geometry once, retaining node bounds and edge paths.

  Options: `:label_width` (24), `:gap_cols` (8), `:gap_rows` (3),
  `:max_cols` (400), `:max_rows` (200). Oversize diagrams return an error.
  Rendering options (`:charset`, `:theme`, `:color`) are also accepted.
  """
  @spec layout(diagram :: t(), opts :: keyword()) :: {:ok, Layout.t()} | error()
  def layout(%__MODULE__{} = diagram, opts \\ []) do
    with {:ok, opts} <- Options.cast(opts) do
      checked_layout(place(diagram, opts), opts)
    end
  end

  defp checked_layout({:error, _reason} = error, _opts), do: error

  defp checked_layout(layout, opts),
    do: with(:ok <- Options.fits(layout, opts), do: {:ok, layout})

  defp place(%__MODULE__{type: :flowchart, data: data}, opts), do: Flowchart.layout(data, opts)
  defp place(%__MODULE__{type: :sequence, data: data}, opts), do: Sequence.layout(data, opts)
  defp place(%__MODULE__{type: :c4, data: data}, opts), do: C4.layout(data, opts)
  defp place(%__MODULE__{type: :state, data: data}, opts), do: State.layout(data, opts)
  defp place(%__MODULE__{type: :er, data: data}, opts), do: ER.layout(data, opts)

  @doc "Layouts and draws a diagram as a frame, ready for any existing renderer."
  @spec render(diagram :: t(), opts :: keyword()) :: {:ok, Ascii.Frame.t()} | error()
  def render(diagram, opts \\ []) do
    with {:ok, layout} <- layout(diagram, opts), do: Layout.frame(layout, opts)
  end

  @doc """
  Changes the optional foreground styles of one identified element.

  Targets are `{:node, id}`, `{:edge, id}`, `{:boundary, id}`, and for
  sequences `{:fragment, id}`, `{:note, id}`, `{:activation, id}`; ER attributes
  use `{:attribute, entity_id, name}`.
  Styles take `:color`, `:label_color`, `:border_color`, `:line_color`;
  a `nil` value clears an override. Colours use `Ascii.Ink.color/1`.
  Styles do not affect geometry. Unknown IDs and invalid colours are errors.
  """
  @spec put_style(diagram :: t(), target :: Layout.target(), style :: map() | keyword()) ::
          {:ok, t()} | error()
  def put_style(%__MODULE__{type: :er, data: data} = diagram, {:attribute, id, name}, style) do
    with {:ok, style} <- Style.cast(style),
         {:ok, entities} <- ER.attribute_style(data.entities, id, name, style),
         do: {:ok, %{diagram | data: %{data | entities: entities}}}
  end

  def put_style(%__MODULE__{} = diagram, {kind, id}, style) do
    with {:ok, style} <- Style.cast(style), do: Style.update(diagram, kind, id, style)
  end

  def put_style(_diagram, target, _style),
    do: {:error, {:invalid_diagram, {:style_target, target}}}
end
