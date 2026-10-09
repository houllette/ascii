defmodule Ascii.Mermaid.Styles do
  @moduledoc false
  alias Ascii.{Diagram.Style, Mermaid.Syntax}

  @spec css(text :: String.t(), target :: :node | :edge) :: {:ok, map()} | :error
  def css(text, target) do
    fields =
      if target == :node,
        do: %{"color" => :label_color, "stroke" => :border_color},
        else: %{"color" => :label_color, "stroke" => :line_color}

    cast_pairs(split(text), fields, ~r/\A\s*([A-Za-z]+)\s*:\s*(.+)\z/s)
  end

  @spec named(text :: String.t(), target :: :node | :edge) :: {:ok, [String.t()], map()} | :error
  def named(text, target) do
    fields =
      if target == :node,
        do: %{"fontColor" => :label_color, "borderColor" => :border_color},
        else: %{"textColor" => :label_color, "lineColor" => :line_color}

    {ids, pairs} =
      text |> split() |> Enum.split_while(&(not String.starts_with?(String.trim(&1), "$")))

    with {:ok, ids} <- ids(ids),
         {:ok, style} <- cast_pairs(pairs, fields, ~r/\A\s*\$([A-Za-z]+)\s*=\s*(.+)\z/s),
         do: {:ok, ids, style}
  end

  defp ids(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case Syntax.label(value) do
        {:ok, id} -> {:cont, {:ok, acc ++ [id]}}
        _ -> {:halt, :error}
      end
    end)
  end

  defp cast_pairs([], _fields, _regex), do: :error

  defp cast_pairs(values, fields, regex) do
    Enum.reduce_while(values, {:ok, %{}}, fn value, {:ok, acc} ->
      with [_, property, color] <- Regex.run(regex, value),
           {:ok, key} <- Map.fetch(fields, property),
           {:ok, color} <- Syntax.label(color),
           {:ok, style} <- Style.cast(%{key => color}) do
        {:cont, {:ok, Map.merge(acc, style)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp split(text), do: split(String.to_charlist(text), [], [], 0, false)

  defp split([], current, out, _depth, _quoted),
    do: Enum.reverse([current |> Enum.reverse() |> List.to_string() | out])

  defp split([?\\, ch | rest], current, out, depth, true),
    do: split(rest, [ch, ?\\ | current], out, depth, true)

  defp split([?" | rest], current, out, depth, quoted),
    do: split(rest, [?" | current], out, depth, not quoted)

  defp split([?( | rest], current, out, depth, false),
    do: split(rest, [?( | current], out, depth + 1, false)

  defp split([?) | rest], current, out, depth, false),
    do: split(rest, [?) | current], out, depth - 1, false)

  defp split([?, | rest], current, out, 0, false),
    do: split(rest, [], [current |> Enum.reverse() |> List.to_string() | out], 0, false)

  defp split([ch | rest], current, out, depth, quoted),
    do: split(rest, [ch | current], out, depth, quoted)
end
