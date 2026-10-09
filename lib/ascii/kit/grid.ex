defmodule Ascii.Kit.Grid do
  @moduledoc """
  A picture being drawn cell by cell: upstream's `string[][]` filled with
  spaces and written into, here a sparse map over a blank.

  Writes out of range are ignored, as most pieces' `put` helpers do; later
  writes win. Each cell holds one character as a binary.
  """

  @type t :: %__MODULE__{
          cols: pos_integer(),
          rows: pos_integer(),
          cells: %{non_neg_integer() => String.t()}
        }

  defstruct [:cols, :rows, cells: %{}]

  @doc "A blank grid."
  @spec new(cols :: pos_integer(), rows :: pos_integer()) :: t()
  def new(cols, rows), do: %__MODULE__{cols: cols, rows: rows}

  @doc "Writes one character at column `x`, row `y`, if that is inside."
  @spec put(grid :: t(), x :: integer(), y :: integer(), ch :: String.t()) :: t()
  def put(%__MODULE__{cols: cols, rows: rows} = grid, x, y, ch)
      when x >= 0 and x < cols and y >= 0 and y < rows,
      do: %{grid | cells: Map.put(grid.cells, y * cols + x, ch)}

  def put(grid, _x, _y, _ch), do: grid

  @doc "Writes a string's characters from column `x` along row `y`."
  @spec put_string(grid :: t(), x :: integer(), y :: integer(), s :: String.t()) :: t()
  def put_string(grid, x, y, s) do
    s
    |> String.codepoints()
    |> Enum.with_index(x)
    |> Enum.reduce(grid, fn {ch, cx}, g -> put(g, cx, y, ch) end)
  end

  @doc "The character at `x`, `y`, or `default` where nothing was written (or outside)."
  @spec get(grid :: t(), x :: integer(), y :: integer(), default :: term()) :: String.t() | term()
  def get(grid, x, y, default \\ " ")

  def get(%__MODULE__{cols: cols, rows: rows} = grid, x, y, default)
      when x >= 0 and x < cols and y >= 0 and y < rows,
      do: Map.get(grid.cells, y * cols + x, default)

  def get(_grid, _x, _y, default), do: default

  @doc "Whether anything was written at `x`, `y`."
  @spec written?(grid :: t(), x :: integer(), y :: integer()) :: boolean()
  def written?(%__MODULE__{cols: cols} = grid, x, y), do: Map.has_key?(grid.cells, y * cols + x)

  @doc "The picture: `rows` lines joined by newlines, `blank` where nothing was written."
  @spec to_iodata(grid :: t(), blank :: String.t()) :: iodata()
  def to_iodata(%__MODULE__{cols: cols, rows: rows, cells: cells}, blank \\ " ") do
    for r <- 0..(rows - 1) do
      base = r * cols
      line = for c <- 0..(cols - 1), do: Map.get(cells, base + c, blank)
      if r < rows - 1, do: [line, ?\n], else: line
    end
  end
end
