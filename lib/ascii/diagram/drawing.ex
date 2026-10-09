defmodule Ascii.Diagram.Drawing do
  @moduledoc false
  alias Ascii.Diagram.Text

  @spec wrap(text :: String.t(), width :: pos_integer()) :: [String.t()]
  def wrap(text, width) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(String.codepoints(&1), width))
  end

  defp wrap_line(codepoints, width) do
    case Enum.split(codepoints, width) do
      {line, []} ->
        [Enum.join(line)]

      {line, overflow} ->
        case break_line(line, overflow) do
          {[], rest} -> wrap_rest(rest, width)
          {line, rest} -> [Enum.join(line) | wrap_rest(rest, width)]
        end
    end
  end

  defp wrap_rest([], _width), do: []
  defp wrap_rest(codepoints, width), do: wrap_line(codepoints, width)

  defp break_line(line, [next | rest] = overflow) do
    # Include the next cell so a space exactly at the width boundary is a break.
    {word, before_word} = Enum.split_while(Enum.reverse(line ++ [next]), &(&1 != " "))

    case {word, before_word, Enum.drop_while(before_word, &(&1 == " "))} do
      {_, [], _} ->
        {line, overflow}

      {[], _, []} ->
        {line, overflow}

      {_, _, prefix} ->
        {Enum.reverse(prefix), Enum.drop_while(Enum.reverse(word) ++ rest, &(&1 == " "))}
    end
  end

  @spec node(node :: map(), opts :: keyword()) :: map()
  def node(node, opts) do
    lines = wrap(node.label, opts[:label_width])
    width = max(lines |> Enum.map(&Text.width/1) |> Enum.max(), 3)
    shape = Map.get(node, :shape, :rectangle)
    {w, h} = dimensions(shape, width, length(lines))
    Map.merge(node, %{lines: lines, width: w, height: h, shape: shape})
  end

  defp dimensions(:diamond, width, rows), do: {width + 2 * rows + 6, 2 * rows + 5}
  defp dimensions(shape, _width, _rows) when shape in [:initial, :final], do: {5, 3}
  defp dimensions(_shape, width, rows), do: {width + 4, rows + 2}

  @spec box(node :: map(), role :: atom()) :: tuple()
  def box(node, role \\ :node), do: {:box, node, role}

  @spec path(edge :: map()) :: tuple()
  def path(edge), do: {:path, edge}

  @spec edge_label(edge :: map()) :: [tuple()]
  def edge_label(%{label: ""}), do: []

  def edge_label(edge), do: [{:edge_label, edge}]

  @spec extent(nodes :: map(), edges :: [map()], boundaries :: map()) ::
          {pos_integer(), pos_integer()}
  def extent(nodes, edges, boundaries \\ %{}) do
    bounds = Map.values(nodes) ++ Map.values(boundaries)
    points = Enum.flat_map(edges, & &1.points)

    labels =
      Enum.map(
        edges,
        &{&1.label_x + max_line(&1.label_lines), &1.label_y + length(&1.label_lines)}
      )

    xs =
      Enum.map(bounds, &(&1.x + &1.width)) ++
        Enum.map(points, &(elem(&1, 0) + 1)) ++ Enum.map(labels, &elem(&1, 0))

    ys =
      Enum.map(bounds, &(&1.y + &1.height)) ++
        Enum.map(points, &(elem(&1, 1) + 1)) ++ Enum.map(labels, &elem(&1, 1))

    {Enum.max(xs, fn -> 1 end), Enum.max(ys, fn -> 1 end)}
  end

  defp max_line(lines), do: lines |> Enum.map(&Text.width/1) |> Enum.max(fn -> 0 end)
end
