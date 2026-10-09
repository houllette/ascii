defmodule Ascii.Diagram.Layout do
  @moduledoc """
  Compiled cell geometry for a diagram, reusable for drawing and hit testing.

  Node, boundary, fragment, note and activation bounds use zero-based
  `x`, `y`, `width`, `height`.
  Edges retain their ordered orthogonal `points` and stable IDs. Bounds and
  routes are independent of theme and character set. `frame/2` does no parsing
  or layout work.
  """

  alias Ascii.Diagram.{Canvas, LayoutStyle, Options, Style, Text, Viewport}

  @type target :: {atom(), String.t()} | {:attribute, String.t(), String.t()}

  @type t :: %__MODULE__{
          cols: pos_integer(),
          rows: pos_integer(),
          nodes: map(),
          boundaries: map(),
          fragments: map(),
          activations: map(),
          notes: map(),
          edges: [map()],
          commands: [tuple()],
          description: String.t()
        }
  @enforce_keys [:cols, :rows]
  defstruct [
    :cols,
    :rows,
    nodes: %{},
    boundaries: %{},
    fragments: %{},
    activations: %{},
    notes: %{},
    edges: [],
    commands: [],
    description: ""
  ]

  @doc "Draws retained geometry. `charset: :ascii | :unicode`, `theme:` maps visual roles to inks."
  @spec frame(layout :: t(), opts :: keyword()) ::
          {:ok, Ascii.Frame.t()} | Ascii.Diagram.error()
  def frame(%__MODULE__{} = layout, opts \\ []) do
    with {:ok, opts} <- Options.cast(opts),
         :ok <- Options.fits(layout, opts),
         do: Canvas.frame(layout, opts)
  end

  @doc "Creates a reusable window with `:x`, `:y`, `:cols` and `:rows` cell coordinates."
  @spec viewport(layout :: t(), opts :: keyword()) :: {:ok, Viewport.t()} | Ascii.Diagram.error()
  def viewport(%__MODULE__{} = layout, opts \\ []), do: Viewport.new(layout, opts)

  @doc "Changes an element's foreground style without parsing, placement or routing. `nil` clears an override."
  @spec put_style(layout :: t(), target :: target(), style :: map() | keyword()) ::
          {:ok, t()} | Ascii.Diagram.error()
  def put_style(%__MODULE__{} = layout, target, style) do
    with {:ok, style} <- Style.cast(style), do: LayoutStyle.put(layout, target, style)
  end

  @doc "The element at a cell, as `{kind, id}`, an ER `{:attribute, entity_id, name}`, or `nil`."
  @spec hit_at(layout :: t(), x :: integer(), y :: integer()) :: target() | nil
  def hit_at(%__MODULE__{cols: cols, rows: rows} = layout, x, y)
      when is_integer(x) and is_integer(y) and x >= 0 and y >= 0 and x < cols and y < rows do
    node = Enum.find(layout.nodes, fn {_id, bounds} -> inside?(bounds, x, y) end)
    note = Enum.find(layout.notes, fn {_id, bounds} -> inside?(bounds, x, y) end)
    activation = Enum.find(layout.activations, fn {_id, bounds} -> inside?(bounds, x, y) end)
    edge = Enum.find(layout.edges, &on_edge?(&1, x, y))
    boundary = at_border(layout.boundaries, x, y)
    fragment = at_border(layout.fragments, x, y)

    if node,
      do: node_target(node, x, y),
      else: hit(nil, note, activation, edge, fragment, boundary)
  end

  def hit_at(_layout, _x, _y), do: nil

  defp node_target({id, node}, x, y) do
    attribute =
      Enum.find(Map.get(node, :attributes, []), fn attribute ->
        x > node.x and x < node.x + node.width - 1 and y >= node.y + attribute.row and
          y < node.y + attribute.row + length(attribute.lines)
      end)

    if attribute, do: {:attribute, id, attribute.name}, else: {:node, id}
  end

  defp hit(nil, {id, _}, _activation, _edge, _fragment, _boundary), do: {:note, id}
  defp hit(nil, nil, {id, _}, _edge, _fragment, _boundary), do: {:activation, id}
  defp hit(nil, nil, nil, %{id: id}, _fragment, _boundary), do: {:edge, id}
  defp hit(nil, nil, nil, nil, {id, _}, _boundary), do: {:fragment, id}
  defp hit(nil, nil, nil, nil, nil, {id, _}), do: {:boundary, id}
  defp hit(nil, nil, nil, nil, nil, nil), do: nil

  defp at_border(bounds, x, y) do
    bounds
    |> Enum.sort_by(fn {_id, b} -> b.width * b.height end)
    |> Enum.find(fn {_id, b} -> border?(b, x, y) end)
  end

  defp inside?(b, x, y), do: x >= b.x and y >= b.y and x < b.x + b.width and y < b.y + b.height

  defp border?(b, x, y),
    do:
      inside?(b, x, y) and
        (x in [b.x, b.x + b.width - 1] or y in [b.y, b.y + b.height - 1] or
           Enum.any?(Map.get(b, :dividers, []), fn {row, _label} -> y == row end))

  defp on_edge?(edge, x, y) do
    label? =
      Enum.any?(Enum.with_index(edge.label_lines), fn {line, row} ->
        y == edge.label_y + row and x >= edge.label_x and x < edge.label_x + Text.width(line)
      end)

    label? or
      Enum.any?(Enum.chunk_every(edge.points, 2, 1, :discard), fn
        [{ax, ay}, {bx, by}] ->
          x >= min(ax, bx) and x <= max(ax, bx) and y >= min(ay, by) and y <= max(ay, by)
      end)
  end
end
