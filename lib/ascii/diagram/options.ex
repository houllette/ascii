defmodule Ascii.Diagram.Options do
  @moduledoc false
  alias Ascii.Ink

  @defaults [
    charset: :unicode,
    color: true,
    theme: %{},
    label_width: 24,
    gap_cols: 8,
    gap_rows: 3,
    max_cols: 400,
    max_rows: 200
  ]
  @roles [:node, :label, :edge, :edge_label, :boundary, :lifeline, :fragment, :note, :activation]

  @spec cast(opts :: term()) :: {:ok, keyword()} | Ascii.Diagram.error()
  def cast(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Enum.reduce_while(opts, {:ok, @defaults}, fn {key, value}, {:ok, acc} ->
        if valid?(key, value),
          do: {:cont, {:ok, Keyword.put(acc, key, value)}},
          else: {:halt, {:error, {:invalid_option, key}}}
      end)
    else
      {:error, {:invalid_option, :options}}
    end
  end

  def cast(_opts), do: {:error, {:invalid_option, :options}}

  defp valid?(:charset, value), do: value in [:ascii, :unicode]
  defp valid?(:color, value), do: is_boolean(value)
  defp valid?(:label_width, value), do: is_integer(value) and value in 4..80
  defp valid?(:gap_cols, value), do: is_integer(value) and value in 4..64
  defp valid?(:gap_rows, value), do: is_integer(value) and value in 2..64
  defp valid?(:max_cols, value), do: is_integer(value) and value in 1..2000
  defp valid?(:max_rows, value), do: is_integer(value) and value in 1..1000

  defp valid?(:theme, value) when is_map(value) do
    Enum.all?(value, fn {role, ink} ->
      role in @roles and (ink == nil or Ink.color(ink) != nil)
    end)
  end

  defp valid?(_key, _value), do: false

  @spec fits(
          size :: %{
            required(:cols) => pos_integer(),
            required(:rows) => pos_integer(),
            optional(atom()) => term()
          },
          opts :: keyword()
        ) ::
          :ok | Ascii.Diagram.error()
  def fits(layout, opts) do
    if layout.cols <= opts[:max_cols] and layout.rows <= opts[:max_rows] and
         layout.cols * layout.rows <= 200_000,
       do: :ok,
       else: {:error, {:too_large, {layout.cols, layout.rows}}}
  end
end
