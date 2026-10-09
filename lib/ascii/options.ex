defmodule Ascii.Options do
  @moduledoc """
  Checks options from outside (code, LiveView params and session, the CLI)
  against a piece's defaults.

  Every key must name one of the piece's options. String keys are compared
  with the names of the defaults, so input never creates an atom. Every value
  must have the shape of its default:

  | default | accepted |
  | --- | --- |
  | number | a number, or a string that reads as one |
  | boolean | a boolean, or `"true"` / `"false"` |
  | string | a valid UTF-8 string, cut to #{256} characters |
  | `nil` | `nil`, or a number as above |
  | list | a list whose entries match the default's entries (any string, if the default is empty); or JSON text for one; or, for a list of strings, comma-separated text, each entry trimmed |
  | map | a map whose keys name some default entry's keys, values checked the same way |

  Numbers are clamped to the piece's `meta.bounds` for that option, or to
  ±1,000,000. A bound reaches inside an option that holds lists or maps: a
  range `{lo, hi}` holds every number within it, and a map of ranges by key
  holds each map's values, `%{processes: %{pid: {0, 4_294_967_295}}}`; a
  number with no range of its own keeps the million. Lists are cut to 256
  entries.

  Where a default cannot show what an option takes (an empty list that takes
  numbers), the piece's `meta.shapes` gives an example to check against
  instead: `%{values: [0.0]}` takes a list of numbers.
  """

  alias Ascii.Meta

  @max_number 1_000_000
  @max_string 256
  @max_list 256

  @type error :: {:error, {:invalid_option, term()}}

  @doc """
  The piece's options: `base` (its defaults, unless given), with `given`
  cast and merged over them.
  """
  @spec cast(meta :: Meta.t(), given :: map() | keyword(), base :: map() | nil) ::
          {:ok, map()} | error()
  def cast(%Meta{options: defaults, bounds: bounds, shapes: shapes}, given, base \\ nil)
      when is_map(given) or is_list(given) do
    Enum.reduce_while(given, {:ok, base || defaults}, fn
      {key, value}, {:ok, acc} ->
        with {:ok, name} <- known_key(defaults, key),
             shape = Map.get_lazy(shapes, name, fn -> Map.fetch!(defaults, name) end),
             {:ok, value} <- cast_value(shape, value, Map.get(bounds, name)) do
          {:cont, {:ok, Map.put(acc, name, value)}}
        else
          :error -> {:halt, {:error, {:invalid_option, key}}}
        end

      other, _acc ->
        {:halt, {:error, {:invalid_option, other}}}
    end)
  end

  @doc """
  The atom naming one of `defaults`' keys, given that atom or its name as a
  string. Never creates an atom.
  """
  @spec known_key(defaults :: map(), key :: term()) :: {:ok, atom()} | :error
  def known_key(defaults, key) when is_atom(key) do
    if Map.has_key?(defaults, key), do: {:ok, key}, else: :error
  end

  def known_key(defaults, key) when is_binary(key) do
    case Enum.find(Map.keys(defaults), &(Atom.to_string(&1) == key)) do
      nil -> :error
      name -> {:ok, name}
    end
  end

  def known_key(_defaults, _key), do: :error

  defp cast_value(default, value, bounds) when is_number(default), do: number(value, bounds)
  defp cast_value(nil, nil, _bounds), do: {:ok, nil}
  defp cast_value(nil, value, bounds), do: number(value, bounds)
  defp cast_value(default, value, _bounds) when is_boolean(default), do: boolean(value)
  defp cast_value(default, value, _bounds) when is_binary(default), do: string(value)
  defp cast_value(default, value, bounds) when is_list(default), do: list(default, value, bounds)
  defp cast_value(default, value, bounds) when is_map(default), do: map(default, value, bounds)
  defp cast_value(_default, _value, _bounds), do: :error

  defp number(value, bounds) when is_number(value), do: {:ok, clamp(value, bounds)}

  defp number(value, bounds) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} ->
        {:ok, clamp(n, bounds)}

      _ ->
        case Float.parse(value) do
          {x, ""} -> {:ok, clamp(x, bounds)}
          _ -> :error
        end
    end
  end

  defp number(_value, _bounds), do: :error

  defp clamp(x, {lo, _hi}) when x < lo, do: same_kind(lo, x)
  defp clamp(x, {_lo, hi}) when x > hi, do: same_kind(hi, x)
  defp clamp(x, {_lo, _hi}), do: x
  defp clamp(x, _none), do: clamp(x, {-@max_number, @max_number})

  defp same_kind(bound, x) when is_float(x), do: bound * 1.0
  defp same_kind(bound, _x), do: bound

  defp boolean(value) when is_boolean(value), do: {:ok, value}
  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(_value), do: :error

  defp string(value) when is_binary(value) do
    if String.valid?(value), do: {:ok, String.slice(value, 0, @max_string)}, else: :error
  end

  defp string(_value), do: :error

  # Every entry takes the list's bound: a range, or ranges by key for maps.
  defp list(default, value, bounds) when is_binary(value) do
    case JSON.decode(value) do
      {:ok, decoded} when is_list(decoded) ->
        list(default, decoded, bounds)

      _ ->
        if strings?(default), do: list(default, split(value), bounds), else: :error
    end
  end

  defp list(default, value, bounds) when is_list(value) do
    template = template(default)

    value
    |> Enum.take(@max_list)
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case cast_value(template, entry, bounds) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end

  defp list(_default, _value, _bounds), do: :error

  # Comma-separated text, as from a form or a command line: "a, b" is
  # ["a", "b"].
  defp split(text), do: text |> String.split(",") |> Enum.map(&String.trim/1)

  defp strings?([]), do: true
  defp strings?([s | _]), do: is_binary(s)

  # What every entry of a default list looks like: an empty list holds
  # strings, a list of maps any key some entry has.
  defp template([]), do: ""

  defp template([first | _] = entries) when is_map(first),
    do: Enum.reduce(entries, %{}, &Map.merge(&1, &2))

  defp template([first | _]), do: first

  defp map(default, value, bounds) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, v}, {:ok, acc} ->
      with {:ok, name} <- known_key(default, key),
           {:ok, v} <- cast_value(Map.fetch!(default, name), v, field(bounds, name)) do
        {:cont, {:ok, Map.put(acc, name, v)}}
      else
        :error -> {:halt, :error}
      end
    end)
  end

  defp map(_default, _value, _bounds), do: :error

  # A key's own range from ranges by key; a range holds every key's numbers.
  defp field(bounds, name) when is_map(bounds), do: Map.get(bounds, name)
  defp field(bounds, _name), do: bounds
end
