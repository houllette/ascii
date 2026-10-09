defmodule Ascii.Mermaid.Syntax do
  @moduledoc false
  @type position :: {String.t(), pos_integer(), pos_integer()}

  @spec match(regex :: Regex.t(), text :: String.t(), groups :: pos_integer()) ::
          [String.t()] | nil
  def match(regex, text, groups) do
    case Regex.run(regex, text) do
      nil -> nil
      matches -> matches ++ List.duplicate("", max(0, groups + 1 - length(matches)))
    end
  end

  @spec statements(source :: String.t()) :: [position()]
  def statements(source), do: scan(String.to_charlist(source), [], [], 1, 1, 1, 1, false)

  defp scan([], chars, out, _line, _column, start_line, start_column, _quoted),
    do: Enum.reverse(add(chars, out, start_line, start_column))

  defp scan([?%, ?% | rest], chars, out, line, column, sl, sc, false) do
    if Enum.all?(chars, &(&1 in [32, 9, 13])) do
      {comment, rest} = Enum.split_while(rest, &(&1 != 10))
      scan(rest, chars, out, line, column + length(comment) + 2, sl, sc, false)
    else
      scan(rest, [?%, ?% | chars], out, line, column + 2, sl, sc, false)
    end
  end

  defp scan([?\\, ch | rest], chars, out, line, column, sl, sc, true),
    do: scan(rest, [ch, ?\\ | chars], out, line, column + 2, sl, sc, true)

  defp scan([?" | rest], chars, out, line, column, sl, sc, quoted),
    do: scan(rest, [?" | chars], out, line, column + 1, sl, sc, not quoted)

  defp scan([ch | rest], chars, out, line, column, sl, sc, false) when ch in [?\n, ?;] do
    next_line = line + if(ch == ?\n, do: 1, else: 0)
    next_column = if ch == ?\n, do: 1, else: column + 1
    scan(rest, [], add(chars, out, sl, sc), next_line, next_column, next_line, next_column, false)
  end

  defp scan([?\n | rest], chars, out, line, _column, sl, sc, true),
    do: scan(rest, [?\n | chars], out, line + 1, 1, sl, sc, true)

  defp scan([ch | rest], chars, out, line, column, sl, sc, quoted),
    do: scan(rest, [ch | chars], out, line, column + 1, sl, sc, quoted)

  defp add(chars, out, line, column) do
    raw = chars |> Enum.reverse() |> List.to_string()
    text = String.trim(raw)

    if text == "" or String.starts_with?(text, "%%"),
      do: out,
      else: [{text, line, column + byte_size(raw) - byte_size(String.trim_leading(raw))} | out]
  end

  @spec error(position :: position(), message :: String.t(), offset :: non_neg_integer()) ::
          Ascii.Mermaid.error()
  def error({_text, line, column}, message, offset \\ 0),
    do: {:error, {:syntax, line, column + offset, message}}

  @spec checked(result :: {:ok, term()} | Ascii.Diagram.error(), position :: position()) ::
          {:ok, term()} | Ascii.Mermaid.error()
  def checked({:ok, _value} = result, _position), do: result

  def checked({:error, reason}, position),
    do: error(position, "invalid diagram: #{inspect(reason)}")

  @spec identifier(text :: String.t()) :: {:ok, String.t(), String.t()} | :error
  def identifier(text) do
    case Regex.run(~r/\A([A-Za-z_][A-Za-z0-9_-]*?)(?=\s|\[|\(|\{|-->|---|-\.->|\z)(.*)\z/s, text) do
      [_, id, rest] -> {:ok, id, String.trim_leading(rest)}
      _ -> :error
    end
  end

  @spec delimited(text :: String.t(), closing :: char()) :: {:ok, String.t(), String.t()} | :error
  def delimited(text, closing), do: delimiter(String.to_charlist(text), closing, [], false)

  defp delimiter([], _closing, _acc, _quoted), do: :error

  defp delimiter([?\\, ch | rest], closing, acc, true),
    do: delimiter(rest, closing, [ch, ?\\ | acc], true)

  defp delimiter([?" | rest], closing, acc, quoted),
    do: delimiter(rest, closing, [?" | acc], not quoted)

  defp delimiter([closing | rest], closing, acc, false),
    do:
      {:ok, acc |> Enum.reverse() |> List.to_string(),
       rest |> List.to_string() |> String.trim_leading()}

  defp delimiter([ch | rest], closing, acc, quoted),
    do: delimiter(rest, closing, [ch | acc], quoted)

  @spec label(text :: String.t()) :: {:ok, String.t()} | :error
  def label(text) do
    text = String.trim(text)

    cond do
      String.starts_with?(text, "\"") -> quoted_label(text)
      String.contains?(text, "\"") -> :error
      true -> {:ok, text}
    end
  end

  defp quoted_label(text) do
    case JSON.decode(text) do
      {:ok, label} when is_binary(label) -> {:ok, label}
      _ -> :error
    end
  end

  @spec upsert(records :: [map()], record :: map()) :: [map()]
  def upsert(records, record) do
    if Enum.any?(records, &(&1.id == record.id)),
      do: Enum.map(records, fn r -> if r.id == record.id, do: record, else: r end),
      else: records ++ [record]
  end

  @spec arguments(text :: String.t()) :: {:ok, [String.t()]} | :error
  def arguments(text), do: args(String.to_charlist(text), [], [], false)
  defp args([], _current, _out, true), do: :error

  defp args([], current, out, false),
    do: finish_args([current |> Enum.reverse() |> List.to_string() | out])

  defp args([?\\, ch | rest], current, out, true), do: args(rest, [ch, ?\\ | current], out, true)
  defp args([?" | rest], current, out, quoted), do: args(rest, [?" | current], out, not quoted)

  defp args([?, | rest], current, out, false),
    do: args(rest, [], [current |> Enum.reverse() |> List.to_string() | out], false)

  defp args([ch | rest], current, out, quoted), do: args(rest, [ch | current], out, quoted)

  defp finish_args(raw) do
    raw
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, []}, fn text, {:ok, acc} ->
      case label(text) do
        {:ok, label} -> {:cont, {:ok, [label | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> then(fn
      {:ok, args} -> {:ok, Enum.reverse(args)}
      failure -> failure
    end)
  end
end
