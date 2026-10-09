defmodule Ascii.Diagram do
  @moduledoc """
  Native, data-driven diagrams rendered as `Ascii.Frame`s.

  Flowcharts, sequences and C4 views have separate models and layout
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

  alias Ascii.Diagram.{C4, Flowchart, Layout, Options, Sequence, Style, Validate}

  @type t :: %__MODULE__{type: :flowchart | :sequence | :c4, data: map()}
  @type error ::
          {:error, {:invalid_diagram, term()}}
          | {:error, {:invalid_option, term()}}
          | {:error, {:too_large, {pos_integer(), pos_integer()}}}
          | {:error, {:too_many_colors, pos_integer()}}

  @enforce_keys [:type, :data]
  defstruct [:type, :data]

  @doc "A directed graph. Node IDs and edge endpoints are strings; direction defaults to `:tb`."
  @spec flowchart(nodes :: [map()], edges :: [map()], opts :: keyword()) :: {:ok, t()} | error()
  def flowchart(nodes, edges, opts \\ []) do
    with {:ok, direction} <- Validate.direction(opts),
         {:ok, nodes} <- Validate.nodes(nodes),
         {:ok, edges} <- Validate.edges(edges, nodes) do
      {:ok,
       %__MODULE__{type: :flowchart, data: %{nodes: nodes, edges: edges, direction: direction}}}
    end
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
      layout = place(diagram, opts)
      with :ok <- Options.fits(layout, opts), do: {:ok, layout}
    end
  end

  defp place(%__MODULE__{type: :flowchart, data: data}, opts), do: Flowchart.layout(data, opts)
  defp place(%__MODULE__{type: :sequence, data: data}, opts), do: Sequence.layout(data, opts)
  defp place(%__MODULE__{type: :c4, data: data}, opts), do: C4.layout(data, opts)

  @doc "Layouts and draws a diagram as a frame, ready for any existing renderer."
  @spec render(diagram :: t(), opts :: keyword()) :: {:ok, Ascii.Frame.t()} | error()
  def render(diagram, opts \\ []) do
    with {:ok, layout} <- layout(diagram, opts), do: Layout.frame(layout, opts)
  end

  @doc """
  Changes the optional foreground styles of one identified element.

  Targets are `{:node, id}`, `{:edge, id}`, `{:boundary, id}`, and for
  sequences `{:fragment, id}`, `{:note, id}`, `{:activation, id}`.
  Styles take `:color`, `:label_color`, `:border_color`, `:line_color`;
  a `nil` value clears an override. Colours use `Ascii.Ink.color/1`.
  Styles do not affect geometry. Unknown IDs and invalid colours are errors.
  """
  @spec put_style(diagram :: t(), target :: {atom(), String.t()}, style :: map() | keyword()) ::
          {:ok, t()} | error()
  def put_style(%__MODULE__{} = diagram, {kind, id}, style) do
    with {:ok, style} <- Style.cast(style), do: Style.update(diagram, kind, id, style)
  end

  def put_style(_diagram, target, _style),
    do: {:error, {:invalid_diagram, {:style_target, target}}}
end
