defmodule Ascii.Diagram.Viewport do
  @moduledoc """
  A window onto retained diagram geometry. Origins are non-negative layout
  cell coordinates; output has exactly `cols` by `rows` cells, padded with
  uncoloured spaces beyond the diagram. Panning reuses the original layout.
  Consumer applications own scrolling, selection and event handling.
  """
  alias Ascii.Diagram.{Canvas, Layout, Options}

  @type t :: %__MODULE__{
          layout: Layout.t(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          cols: pos_integer(),
          rows: pos_integer()
        }
  @enforce_keys [:layout, :x, :y, :cols, :rows]
  defstruct [:layout, :x, :y, :cols, :rows]

  @doc "Creates a bounded window. `:cols` and `:rows` default to the layout dimensions."
  @spec new(layout :: Layout.t(), opts :: keyword()) :: {:ok, t()} | Ascii.Diagram.error()
  def new(layout, opts \\ []) do
    if is_list(opts) and Keyword.keyword?(opts) do
      values = [x: 0, y: 0, cols: layout.cols, rows: layout.rows] |> Keyword.merge(opts)

      case Enum.find(values, fn {key, value} -> not valid?(key, value) end) do
        nil ->
          viewport = struct!(__MODULE__, Map.new([{:layout, layout} | values]))
          with :ok <- Options.fits(viewport, max_cols: 2000, max_rows: 1000), do: {:ok, viewport}

        {key, _} ->
          {:error, {:invalid_option, key}}
      end
    else
      {:error, {:invalid_option, :options}}
    end
  end

  defp valid?(key, value) when key in [:x, :y], do: is_integer(value) and value >= 0
  defp valid?(:cols, value), do: is_integer(value) and value in 1..2000
  defp valid?(:rows, value), do: is_integer(value) and value in 1..1000
  defp valid?(_key, _value), do: false

  @doc "Draws only the window's cells; does not allocate a full diagram frame."
  @spec frame(viewport :: t(), opts :: keyword()) ::
          {:ok, Ascii.Frame.t()} | Ascii.Diagram.error()
  def frame(%__MODULE__{} = viewport, opts \\ []) do
    with {:ok, validated} <- Options.cast(opts),
         validated = Keyword.put(validated, :max_cols, Keyword.get(opts, :max_cols, 2000)),
         validated = Keyword.put(validated, :max_rows, Keyword.get(opts, :max_rows, 1000)),
         :ok <- Options.fits(viewport, validated),
         do: Canvas.frame(viewport.layout, validated, viewport)
  end

  @doc "Moves the origin by cell deltas, clamping at zero."
  @spec pan(viewport :: t(), dx :: integer(), dy :: integer()) ::
          {:ok, t()} | Ascii.Diagram.error()
  def pan(%__MODULE__{} = viewport, dx, dy) when is_integer(dx) and is_integer(dy),
    do: {:ok, %{viewport | x: max(0, viewport.x + dx), y: max(0, viewport.y + dy)}}

  def pan(_viewport, _dx, _dy), do: {:error, {:invalid_option, :pan}}

  @doc "Translates a visible cell to layout coordinates; out-of-window cells return `nil`."
  @spec to_layout(viewport :: t(), x :: integer(), y :: integer()) ::
          {non_neg_integer(), non_neg_integer()} | nil
  def to_layout(%__MODULE__{} = viewport, x, y)
      when is_integer(x) and is_integer(y) and x >= 0 and y >= 0 and x < viewport.cols and
             y < viewport.rows,
      do: {viewport.x + x, viewport.y + y}

  def to_layout(_viewport, _x, _y), do: nil

  @doc "Translates a layout cell to window coordinates, returning `nil` outside the window."
  @spec to_viewport(viewport :: t(), x :: integer(), y :: integer()) ::
          {non_neg_integer(), non_neg_integer()} | nil
  def to_viewport(%__MODULE__{} = viewport, x, y) when is_integer(x) and is_integer(y),
    do: local(viewport, x - viewport.x, y - viewport.y)

  def to_viewport(_viewport, _x, _y), do: nil

  defp local(viewport, x, y) when x >= 0 and y >= 0 and x < viewport.cols and y < viewport.rows,
    do: {x, y}

  defp local(_viewport, _x, _y), do: nil

  @doc "Hit tests a window cell against the original layout, retaining element IDs."
  @spec hit_at(viewport :: t(), x :: integer(), y :: integer()) :: Layout.target() | nil
  def hit_at(%__MODULE__{} = viewport, x, y) do
    case to_layout(viewport, x, y) do
      {lx, ly} -> Layout.hit_at(viewport.layout, lx, ly)
      nil -> nil
    end
  end
end
